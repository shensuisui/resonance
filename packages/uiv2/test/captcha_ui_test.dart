/// 人机验证（挂起流程 + 验证面板）测试
///
/// 覆盖：
///   ① 播放控制器：源站要求验证时**挂起挑战**（不是当失败吞掉）；提交验证码后继续播放；
///      验证码错时返回新挑战（就地换图，不重新挂起、不叠面板）；取消则清空挂起。
///   ② 验证面板：渲染验证图与输入框、提交回调拿到验证码、错误时就地提示、换一张回调。
///
/// 模拟数据：手写假源（首次回挑战、带正确验证码回地址）、假播放器（记录 play 调用）、
/// 假播放缓存（不命中）、core 的内存数据库。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:uiv2/src/components/captcha_sheet.dart';
import 'package:uiv2/src/design/theme.dart';
import 'package:uiv2/src/providers/providers.dart';

/// 1×1 透明 PNG（验证图占位；面板只负责显示字节，不做解码正确性断言）
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

/// 假播放缓存：什么都不命中（本用例只关心"回源拿到挑战"这条路）
class _FakeCache implements AudioCache {
  @override
  Future<void> init() async {}

  @override
  Set<String> get cachedKeys => const {};

  @override
  bool isCached(String songKey) => false;

  @override
  String? localUrlFor(String songKey) => null;

  @override
  Future<String?> downloadedUrlFor(Song song) async => null;

  @override
  Future<void> cacheAfterPlay(Song song, String url,
      {Map<String, String>? headers}) async {}

  @override
  Future<int> sizeOnDisk() async => 0;

  @override
  Future<void> clear() async {}

  @override
  Stream<void> get changes => const Stream.empty();
}

/// 假最近播放服务：只实现"记一笔"（起播会走到它）
class _FakeRecentPlays implements RecentPlaysService {
  /// 记录到的曲目
  final List<Song> recorded = [];

  @override
  Future<void> recordPlay(Song song) async => recorded.add(song);

  @override
  Future<List<RecentPlayRecord>> getRecentPlayRecords({int limit = 500}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('假最近播放服务未实现该成员');
}

/// 假播放器：记录 play 调用；三条流显式空实现
class _FakePlayer implements Player {
  /// 收到的播放请求
  final List<Song> played = [];

  @override
  Stream<PlayerState> get stateStream => const Stream.empty();

  @override
  Stream<int> get positionStream => const Stream.empty();

  @override
  Stream<int> get durationStream => const Stream.empty();

  @override
  List<Song> get queue => const [];

  @override
  Future<void> play(Song song) async => played.add(song);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('假播放器未实现该成员');
}

/// 假源：不带验证码时回挑战；带正确验证码时回真实地址
class _StubSource extends MusicSource {
  /// 正确的验证码
  static const String rightCode = 'AB12';

  /// 最近一次收到的验证码（断言"确实按源站字段回传了"）
  String? lastCode;

  @override
  SourceInfo get sourceInfo =>
      SourceInfo(id: 'stub', name: '桩源', type: SourceType.rule);

  @override
  Future<SearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 20,
  }) async =>
      SearchResult(songs: const <Song>[], sourceId: 'stub');

  @override
  Future<Song> getSongDetail(String id) async =>
      Song(id: id, sourceId: 'stub', title: '默', artist: '那英');

  @override
  Future<String> getSongUrl(String id) async => '';

  @override
  Future<PlayableInfo> getPlayable(String id,
      {String? captchaCode, String? captchaKey}) async {
    lastCode = captchaCode;
    final meta = Song(id: id, sourceId: 'stub', title: '默', artist: '那英');
    if (captchaCode == rightCode) {
      return PlayableInfo(url: 'http://audio/' + id + '.mp3', meta: meta);
    }
    return PlayableInfo(
      url: '',
      meta: meta,
      challenge: const PlaybackChallenge(
        image: 'data:image/png;base64,$_png',
        key: 'KEY-1',
        codeField: 'captchaCode',
        keyField: 'key',
        message: '请完成人机验证后继续',
      ),
    );
  }

  @override
  Future<Lyrics?> getLyrics(String id) async => null;

  @override
  Future<Album?> getAlbum(String id) async => null;

  @override
  Future<Artist?> getArtist(String id) async => null;

  @override
  Future<Playlist?> getPlaylist(String id) async => null;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}
}

/// 统一测试宿主：MaterialApp + UiV2Scope + Riverpod
Widget _host(Widget child, {List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: UiV2DesignTheme.dark(),
        builder: (context, c) => c == null ? const SizedBox() : UiV2Scope(child: c),
        home: Scaffold(body: child),
      ),
    );

void main() {
  /// 被测曲目
  const song = Song(id: '1', sourceId: 'stub', title: '默', artist: '那英');

  /// 验证挑战
  const challenge = PlaybackChallenge(
    image: 'data:image/png;base64,$_png',
    key: 'KEY-1',
    codeField: 'captchaCode',
    keyField: 'key',
    message: '请完成人机验证后继续',
  );

  group('挂起流程（播放控制器）', () {
    late ProviderContainer container;
    late _StubSource source;
    late _FakePlayer player;
    late _FakeRecentPlays recent;

    setUp(() async {
      source = _StubSource();
      player = _FakePlayer();
      recent = _FakeRecentPlays();
      final db = InMemoryDatabaseProvider();
      await db.initialize();
      container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        playerProvider.overrideWithValue(player),
        sourceManagerProvider
            .overrideWithValue(SourceManager()..registerSource(source)),
        audioCacheProvider.overrideWithValue(_FakeCache()),
        recentPlaysServiceProvider.overrideWithValue(recent),
      ]);
    });

    tearDown(() => container.dispose());

    test('源站要求验证：挂起挑战而不是当失败吞掉', () async {
      final ok = await container.read(playbackControllerProvider).playSong(song);

      expect(ok, isFalse, reason: '还没开始播，等用户输入验证码');
      expect(player.played, isEmpty);
      final pc = container.read(pendingCaptchaProvider);
      expect(pc, isNotNull);
      expect(pc!.challenge.key, 'KEY-1');
      expect(pc.challenge.image, isNotEmpty);
      expect(pc.challenge.message, contains('人机验证'));
      expect(pc.song.globalKey, song.globalKey, reason: '验证通过后要接着播这一首');
    });

    test('提交正确验证码：开始播放并清空挂起', () async {
      await container.read(playbackControllerProvider).playSong(song);

      final result =
          await container.read(playbackControllerProvider).submitCaptcha('AB12');

      expect(result.ok, isTrue);
      expect(source.lastCode, 'AB12');
      expect(player.played.single.playUrl, contains('/1.mp3'));
      expect(container.read(pendingCaptchaProvider), isNull);
      expect(container.read(currentTrackIdProvider), song.globalKey);
      expect(recent.recorded.single.globalKey, song.globalKey,
          reason: '过了验证就等于正常播放，最近播放要记一笔');
    });

    test('验证码错：返回新挑战供就地重试（不重新挂起、不叠面板）', () async {
      await container.read(playbackControllerProvider).playSong(song);

      final result =
          await container.read(playbackControllerProvider).submitCaptcha('WRONG');

      expect(result.ok, isFalse);
      expect(result.challenge, isNotNull);
      expect(player.played, isEmpty);
    });

    test('取消：清空挂起（界面另行说明原因）', () async {
      await container.read(playbackControllerProvider).playSong(song);
      expect(container.read(pendingCaptchaProvider), isNotNull);

      container.read(playbackControllerProvider).cancelCaptcha();

      expect(container.read(pendingCaptchaProvider), isNull);
    });
  });

  group('验证面板（组件）', () {
    testWidgets('渲染验证图与输入框，提交后回调拿到验证码', (tester) async {
      String? submitted;
      await tester.pumpWidget(_host(UiV2CaptchaSheet(
        challenge: challenge,
        onSubmit: (code) async {
          submitted = code;
          return const CaptchaSubmitResult(ok: true);
        },
      )));
      await tester.pump();

      expect(find.byKey(const ValueKey('captcha_image')), findsOneWidget);
      expect(find.byKey(const ValueKey('captcha_input')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byKey(const ValueKey('captcha_input')), 'AB12');
      await tester.tap(find.byKey(const ValueKey('captcha_submit')));
      await tester.pump();

      expect(submitted, 'AB12');
    });

    testWidgets('验证码错：就地提示，并用返回的新挑战换图', (tester) async {
      await tester.pumpWidget(_host(UiV2CaptchaSheet(
        challenge: challenge,
        onSubmit: (code) async => const CaptchaSubmitResult(
          ok: false,
          challenge: PlaybackChallenge(
            image: 'data:image/png;base64,$_png',
            key: 'KEY-2',
            codeField: 'captchaCode',
            keyField: 'key',
          ),
        ),
      )));
      await tester.pump();

      await tester.enterText(find.byKey(const ValueKey('captcha_input')), 'X');
      await tester.tap(find.byKey(const ValueKey('captcha_submit')));
      await tester.pump();

      expect(find.text('验证码不正确，请重试'), findsOneWidget,
          reason: '就地提示，不弹第二个面板');
      expect(tester.takeException(), isNull);
    });

    testWidgets('换一张：回调被调用且不报错', (tester) async {
      var refreshed = 0;
      await tester.pumpWidget(_host(UiV2CaptchaSheet(
        challenge: challenge,
        onSubmit: (code) async => const CaptchaSubmitResult(ok: true),
        onRefresh: () async {
          refreshed++;
          return null;
        },
      )));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('captcha_refresh')));
      await tester.pump();

      expect(refreshed, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
