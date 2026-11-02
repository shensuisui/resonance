/// 沉浸播放页布局回归测试（手机端整页不可滚）
///
/// 用户要求：手机模式下这个页面**整体不能滑动**，布局方式要调整。
/// 这里钉住两件事：
///   ① 窄屏主体不再包含整页滚动容器（SingleChildScrollView）；
///   ② 正常手机高度与"窗口被拉得很扁"的极端高度下都不溢出（极端走 FittedBox 等比缩小）。
///
/// 模拟数据：内存数据库 + 假播放器（三条流显式空实现），cur 曲目留空即可 ——
/// 布局本身与有没有歌无关，重点是高度分配。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:uiv2/src/components/now_playing.dart';
import 'package:uiv2/src/design/theme.dart';
import 'package:uiv2/src/providers/providers.dart';

/// 假播放缓存
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

/// 假播放器：流空实现 + 只读快照给常量（布局测试只关心尺寸，不关心播放）
class _FakePlayer implements Player {
  @override
  Stream<PlayerState> get stateStream => const Stream.empty();
  @override
  Stream<int> get positionStream => const Stream.empty();
  @override
  Stream<int> get durationStream => const Stream.empty();
  @override
  PlayerState get currentState => PlayerState.idle;
  @override
  int get currentPosition => 0;
  @override
  int get currentDuration => 0;
  @override
  double get volume => 1;
  @override
  PlayMode get playMode => PlayMode.listLoop;
  @override
  set playMode(PlayMode mode) {}
  @override
  List<Song> get queue => const [];
  @override
  int get currentIndex => -1;
  @override
  void setQueue(List<Song> songs) {}
  @override
  Future<void> play(Song song) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> next() async {}
  @override
  Future<void> previous() async {}
  @override
  Future<void> jumpToIndex(int index) async {}
  @override
  Future<void> prepareAt(int index, {Duration position = Duration.zero}) async {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('假播放器未实现该成员');
}

void main() {
  late ProviderContainer container;

  setUp(() async {
    final db = InMemoryDatabaseProvider();
    await db.initialize();
    container = ProviderContainer(overrides: <Override>[
      appDatabaseProvider.overrideWithValue(db),
      playerProvider.overrideWithValue(_FakePlayer()),
      sourceManagerProvider.overrideWithValue(SourceManager()),
      audioCacheProvider.overrideWithValue(_FakeCache()),
    ]);
  });

  tearDown(() => container.dispose());

  /// 在指定逻辑尺寸下渲染播放页
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: UiV2DesignTheme.dark(),
        builder: (context, c) => c == null ? const SizedBox() : UiV2Scope(child: c),
        home: const Scaffold(body: UiV2NowPlayingScreen()),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('手机尺寸：整页没有滚动容器，也不溢出', (tester) async {
    await pumpAt(tester, const Size(444, 781));

    expect(find.byType(SingleChildScrollView), findsNothing,
        reason: '手机端播放页必须整页不可滚（滚动只允许发生在歌词区内部）');
    expect(tester.takeException(), isNull);
  });

  testWidgets('窗口被拉得很扁：等比缩小而不是溢出/滚动', (tester) async {
    await pumpAt(tester, const Size(444, 380));

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull, reason: '极端高度也不能溢出');
  });
}
