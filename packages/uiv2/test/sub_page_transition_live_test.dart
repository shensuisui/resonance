/// 二级页转场「按屏宽分档」的真机等价验证 —— 在过渡**中途**读实际位移
///
/// 为什么不用截图：Flan 截图有往返延迟（>220ms），抓不到 220ms 的过渡中间帧，
/// 拍到的永远是终态（实测两帧 sha 相同）。所以这里直接渲染真实路由、推进到过渡
/// 一半，再读 SlideTransition 的当前 Offset —— 这才是能证明「大屏不横移」的证据。
///
/// 约定：平板（768）与桌面（>=1024）水平位移必须恒为 0；窄屏才允许横向滑入。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:uiv2/src/app_router.dart';
import 'package:uiv2/src/design/theme.dart';
import 'package:uiv2/src/pages/settings_page.dart';
import 'package:uiv2/src/providers/providers.dart';
import 'package:uiv2/src/router.dart';

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

/// 假播放器（布局/转场测试不关心播放，只要不抛异常）
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
      recentPlaysServiceProvider
          .overrideWithValue(RecentPlaysService(db.recentPlaysDao)),
    ]);
  });

  tearDown(() => container.dispose());

  /// 在指定逻辑宽度渲染真实路由，并推进到「进入设置页」过渡的一半，返回该层位移
  Future<Offset> slideAtMidTransition(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: container.read(appRouterProvider),
        theme: UiV2DesignTheme.dark(),
        builder: (context, c) =>
            c == null ? const SizedBox() : UiV2Scope(child: c),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    container.read(navProvider.notifier).go('profile');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    container.read(navProvider.notifier).go('settings');
    await tester.pump(); // 起帧，动画从这一刻开始
    await tester.pump(const Duration(milliseconds: 110)); // 220ms 的一半

    // 找到包住设置页的那层 SlideTransition（最近的祖先）
    final finder = find.ancestor(
      of: find.byType(SettingsPage, skipOffstage: false),
      matching: find.byType(SlideTransition, skipOffstage: false),
    );
    expect(finder, findsWidgets, reason: '二级页应被位移包裹（转场生效）');
    final slide = tester.widget<SlideTransition>(finder.first);
    return slide.position.value;
  }

  testWidgets('平板 900：过渡中途水平位移恒为 0，只轻微上浮', (tester) async {
    final offset = await slideAtMidTransition(tester, 900);
    expect(offset.dx, 0, reason: '平板绝不能让内容横向移动');
    expect(offset.dy, greaterThan(0), reason: '应还在上浮过程中（证明抓到了中途）');
  });

  testWidgets('桌面 1280：过渡中途水平位移恒为 0', (tester) async {
    final offset = await slideAtMidTransition(tester, 1280);
    expect(offset.dx, 0);
    expect(offset.dy, greaterThan(0));
  });

  testWidgets('手机 444：仍然是横向滑入（交界处在过渡中途）', (tester) async {
    final offset = await slideAtMidTransition(tester, 444);
    expect(offset.dx, greaterThan(0), reason: '窄屏保留横向滑入的层级隐喻');
    expect(offset.dy, 0);
  });
}
