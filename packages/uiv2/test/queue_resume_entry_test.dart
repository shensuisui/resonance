/// 续播入口测试（歌单卡片的播放键 + 单曲入口的同曲续播）
///
/// 规则：
///   ① 歌单卡片的播放键 = 「继续播放」：有进度接着上次位置，没进度从头（同一个入口）；
///   ② 单曲入口（搜索/首页卡片/已下载）记入最近播放并切过去；
///   若"上次听到的正是这一首"，要接着上次的位置，而不是从 0:00 重来。
///
/// 模拟数据：桩源一律给地址；假播放器记录 seek；假最近播放服务维护记录列表
/// （最近播放队列由这些记录推导，所以必须真实维护才能测到队首）。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:uiv2/src/design/theme.dart';
import 'package:uiv2/src/providers/providers.dart';
import 'package:uiv2/src/widgets/track_actions.dart';

/// 假播放缓存：不命中
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

/// 假播放器：记录 seek 与在播曲目
class _FakePlayer implements Player, AudibleSongSource {
  List<Song> _queue = const [];
  Song? _audible;

  /// 最近一次 seek
  Duration? lastSeek;

  @override
  Stream<PlayerState> get stateStream => const Stream.empty();
  @override
  Stream<int> get positionStream => const Stream.empty();
  @override
  Stream<int> get durationStream => const Stream.empty();
  @override
  List<Song> get queue => _queue;
  @override
  void setQueue(List<Song> songs) => _queue = List.of(songs);
  @override
  Future<void> play(Song song) async => _audible = song;
  @override
  Future<void> jumpToIndex(int index) async {
    if (index >= 0 && index < _queue.length) _audible = _queue[index];
  }

  @override
  Future<void> prepareAt(int index, {Duration position = Duration.zero}) async {
    if (index >= 0 && index < _queue.length) _audible = _queue[index];
  }

  @override
  Future<void> seek(Duration position) async => lastSeek = position;
  @override
  Song? get audibleSong => _audible;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('假播放器未实现该成员');
}

/// 假最近播放服务：真的维护记录（最近播放队列由记录推导）
class _FakeRecent implements RecentPlaysService {
  /// 记录列表（新→旧）
  final List<RecentPlayRecord> records = [];

  @override
  Future<void> recordPlay(Song song) async {
    records.removeWhere((r) => r.songKey == song.globalKey);
    records.insert(
      0,
      RecentPlayRecord(
        songKey: song.globalKey,
        playedAt: DateTime.now().millisecondsSinceEpoch,
        title: song.title,
        artist: song.artist,
        coverUrl: song.coverUrl,
      ),
    );
  }

  @override
  Future<List<RecentPlayRecord>> getRecentPlayRecords({int limit = 500}) async =>
      List.of(records);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('假最近播放服务未实现该成员');
}

/// 桩源：总是给播放地址
class _StubSource extends MusicSource {
  @override
  SourceInfo get sourceInfo =>
      SourceInfo(id: 'stub', name: '桩源', type: SourceType.rule);
  @override
  Future<PlayableInfo> getPlayable(String id,
      {String? captchaCode, String? captchaKey}) async =>
      PlayableInfo(
          url: 'http://audio/' + id + '.mp3',
          meta: Song(id: id, sourceId: 'stub', title: '曲' + id, artist: ''));
  @override
  Future<SearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 20,
  }) async =>
      SearchResult(songs: const <Song>[], sourceId: 'stub');
  @override
  Future<Song> getSongDetail(String id) async =>
      Song(id: id, sourceId: 'stub', title: '曲' + id, artist: '');
  @override
  Future<String> getSongUrl(String id) async => '';
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

/// 宿主：MaterialApp + UiV2Scope + ProviderScope
Widget _host(Widget child, {List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: UiV2DesignTheme.dark(),
        builder: (context, c) => c == null ? const SizedBox() : UiV2Scope(child: c),
        home: Scaffold(body: child),
      ),
    );

void main() {
  late _FakePlayer player;
  late _FakeRecent recent;
  late InMemoryDatabaseProvider db;

  const songA = Song(id: 'a', sourceId: 'stub', title: '甲', artist: '');
  const songB = Song(id: 'b', sourceId: 'stub', title: '乙', artist: '');

  setUp(() async {
    player = _FakePlayer();
    recent = _FakeRecent();
    db = InMemoryDatabaseProvider();
    await db.initialize();
  });

  List<Override> overrides() => [
        appDatabaseProvider.overrideWithValue(db),
        playerProvider.overrideWithValue(player),
        sourceManagerProvider
            .overrideWithValue(SourceManager()..registerSource(_StubSource())),
        audioCacheProvider.overrideWithValue(_FakeCache()),
        recentPlaysServiceProvider.overrideWithValue(recent),
      ];

  /// 取一个能用的 (context, ref) —— TrackActions 的签名需要这两样
  Future<(BuildContext, WidgetRef)> grab(WidgetTester tester) async {
    late BuildContext ctx;
    late WidgetRef r;
    await tester.pumpWidget(_host(
      Consumer(builder: (context, ref, _) {
        ctx = context;
        r = ref;
        return const SizedBox();
      }),
      overrides: overrides(),
    ));
    await tester.pump();
    return (ctx, r);
  }

  group('单曲入口的同曲续播', () {
    testWidgets('上次听的就是这一首：接着上次位置', (tester) async {
      await db.playProgressDao.upsert(const PlayProgress(
        queueKind: 'recent',
        songKey: 'stub:b',
        positionMs: 60000,
        updatedAt: 1,
      ));

      final (ctx, r) = await grab(tester);
      final started = await TrackActions.playAsRecent(ctx, r, songB);
      await tester.pump();

      expect(started, isTrue);
      expect(player.lastSeek, const Duration(milliseconds: 60000),
          reason: '同一首歌再点一次，期望继续听而不是从 0:00 重来');
    });

    testWidgets('上次是另一首：从 0:00 开始（不瞎 seek）', (tester) async {
      await db.playProgressDao.upsert(const PlayProgress(
        queueKind: 'recent',
        songKey: 'stub:a',
        positionMs: 60000,
        updatedAt: 1,
      ));

      final (ctx, r) = await grab(tester);
      final started = await TrackActions.playAsRecent(ctx, r, songB);
      await tester.pump();

      expect(started, isTrue);
      expect(player.lastSeek, isNull, reason: '点的不是上次那首，就不该带进度');
    });
  });

  group('歌单卡片的播放键 = 继续播放', () {
    const queue = PlayQueue(
      kind: PlayQueueKind.playlist,
      id: 'p1',
      title: '默认1',
      songs: [songA, songB],
    );

    testWidgets('有进度：从记录的曲目与毫秒位置接着播', (tester) async {
      await db.playProgressDao.upsert(const PlayProgress(
        queueKind: 'playlist',
        queueId: 'p1',
        songKey: 'stub:b',
        positionMs: 92000,
        updatedAt: 1,
      ));

      final (ctx, r) = await grab(tester);
      final started = await TrackActions.resume(ctx, r, queue);
      await tester.pump();

      expect(started, isTrue);
      expect(r.read(currentTrackIdProvider), songB.globalKey);
      expect(player.lastSeek, const Duration(milliseconds: 92000));
    });

    testWidgets('没进度：等同从头播（不 seek）', (tester) async {
      final (ctx, r) = await grab(tester);
      final started = await TrackActions.resume(ctx, r, queue);
      await tester.pump();

      expect(started, isTrue);
      expect(r.read(currentTrackIdProvider), songA.globalKey);
      expect(player.lastSeek, isNull);
    });
  });
}
