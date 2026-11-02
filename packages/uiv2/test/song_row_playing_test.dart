/// 曲目行「播放态」与点击语义测试
///
/// 用户规则：
///   ① 播放中样式（底色 + accent 标题 + 半透明遮罩 + 三柱动画）
///      只在**所属队列**的列表里显示；别的页面里那首歌就是普通行；
///   ② 点正在播的那一行 = 暂停；再点 = 继续；
///   ③ 暂停也保留样式：遮罩与三柱都在，只是动画停住。
///
/// 模拟数据：假播放器（记录 pause/resume 并维护状态）+ 手写曲目；
/// 队列身份用 'playlist:p1' 直接摆进 queueProvider。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:uiv2/src/components/rows.dart';
import 'package:uiv2/src/design/theme.dart';
import 'package:uiv2/src/providers/providers.dart';

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

/// 假播放器：pause/resume 会真的改状态，便于断言"点了发生什么"
class _FakePlayer implements Player, AudibleSongSource {
  /// 当前状态（测试里与 isPlayingProvider 一起摆，模拟真实同步）
  PlayerState state = PlayerState.paused;
  final List<String> calls = [];

  @override
  Stream<PlayerState> get stateStream => const Stream.empty();
  @override
  Stream<int> get positionStream => const Stream.empty();
  @override
  Stream<int> get durationStream => const Stream.empty();
  @override
  PlayerState get currentState => state;
  @override
  List<Song> get queue => const [];
  @override
  void setQueue(List<Song> songs) {}
  @override
  Future<void> pause() async {
    calls.add('pause');
    state = PlayerState.paused;
  }

  @override
  Future<void> resume() async {
    calls.add('resume');
    state = PlayerState.playing;
  }

  @override
  Song? get audibleSong => null;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('假播放器未实现该成员');
}

void main() {
  const song = Song(id: 'x', sourceId: 'stub', title: '赤伶', artist: 'HITA');
  const queue = PlayQueue(
    kind: PlayQueueKind.playlist,
    id: 'p1',
    title: '默认1',
    songs: [song],
  );

  late ProviderContainer container;
  late _FakePlayer player;
  var taps = 0;

  setUp(() async {
    player = _FakePlayer();
    taps = 0;
    final db = InMemoryDatabaseProvider();
    await db.initialize();
    container = ProviderContainer(overrides: <Override>[
      appDatabaseProvider.overrideWithValue(db),
      playerProvider.overrideWithValue(player),
      sourceManagerProvider.overrideWithValue(SourceManager()),
      audioCacheProvider.overrideWithValue(_FakeCache()),
    ]);
  });

  tearDown(() => container.dispose());

  /// 摆好状态并渲染一行
  Future<void> pumpRow(
    WidgetTester tester, {
    required String? queueIdentity,
    required bool current,
    required bool playing,
  }) async {
    container.read(queueProvider.notifier).setQueue(queue);
    container.read(currentTrackIdProvider.notifier).set(current ? song.globalKey : null);
    container.read(isPlayingProvider.notifier).set(playing);
    // 真实环境里播放器状态与 isPlayingProvider 是同步的，测试也要一起摆，
    // 否则 toggle() 会读到过期状态（这里踩过一次：点"暂停"却走了 resume）
    player.state = playing ? PlayerState.playing : PlayerState.paused;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: UiV2DesignTheme.dark(),
        builder: (context, c) => c == null ? const SizedBox() : UiV2Scope(child: c),
        home: Scaffold(
          body: UiV2SongRow(
            song: song,
            index: 0,
            queueIdentity: queueIdentity,
            onTap: () => taps++,
            onToggleLike: () {},
            onMore: () {},
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('非当前曲目：普通行，点击走原动作', (tester) async {
    await pumpRow(tester, queueIdentity: 'playlist:p1', current: false, playing: true);

    expect(find.byType(UiV2Eq), findsNothing);
    await tester.tap(find.byType(UiV2SongRow));
    await tester.pump();
    expect(taps, 1);
    expect(player.calls, isEmpty);
  });

  testWidgets('当前 + 属于本队列 + 播放中：显示动画，点击=暂停', (tester) async {
    await pumpRow(tester, queueIdentity: 'playlist:p1', current: true, playing: true);

    final eq = tester.widget<UiV2Eq>(find.byType(UiV2Eq));
    expect(eq.animated, isTrue, reason: '播放中三柱应该在动');

    await tester.tap(find.byType(UiV2SongRow));
    await tester.pump();
    expect(player.calls, ['pause'], reason: '点正在播的那一行 = 暂停');
    expect(taps, 0, reason: '不应再触发"切过去并播这首"');
  });

  testWidgets('当前 + 属于本队列 + 暂停：样式仍在但动画停住，点击=继续', (tester) async {
    await pumpRow(tester, queueIdentity: 'playlist:p1', current: true, playing: false);

    final eq = tester.widget<UiV2Eq>(find.byType(UiV2Eq));
    expect(eq.animated, isFalse, reason: '暂停只把动画停掉，样式要保留');

    await tester.tap(find.byType(UiV2SongRow));
    await tester.pump();
    expect(player.calls, ['resume'], reason: '再点一下 = 继续播放');
    expect(taps, 0);
  });

  testWidgets('当前但不属于本队列：不显示播放态，点击走原动作', (tester) async {
    await pumpRow(tester, queueIdentity: 'recent', current: true, playing: true);

    expect(find.byType(UiV2Eq), findsNothing,
        reason: '别的队列页里那首歌不该染播放态');

    await tester.tap(find.byType(UiV2SongRow));
    await tester.pump();
    expect(taps, 1);
    expect(player.calls, isEmpty);
  });

  testWidgets('非队列列表（搜索/推荐）：即使正在播也不显示播放态', (tester) async {
    await pumpRow(tester, queueIdentity: null, current: true, playing: true);

    expect(find.byType(UiV2Eq), findsNothing);
    await tester.tap(find.byType(UiV2SongRow));
    await tester.pump();
    expect(taps, 1);
  });
}
