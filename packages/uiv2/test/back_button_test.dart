/// 系统返回键行为回归测试（Issue #5 第 3 条）
///
/// 现场：安卓上一级页按返回键直接把 App 退掉了；沉浸播放页开着按返回也是退出。
/// 现在系统返回在外壳（UiV2AppShell 的 PopScope）统一接管：
///   * 二级页：由分支 Navigator 正常出栈（返回上一页）；
///   * 移动端二级一级页（liked/local）：退到上一级（与顶栏返回键同路径）；
///   * 一级页：第一按只提示「再按一次返回键退出」，两秒内再按才真正退出；
///   * 沉浸播放页开着：先收起播放页。
///
/// 系统返回在测试里用 `tester.binding.handlePopRoute()` 触发 —— 与安卓返回键
/// 走同一条 WidgetsBinding 分发路径（Router → GoRouterDelegate.popRoute）。
/// 退出动作走 SystemNavigator 的平台通道，这里 mock 住通道记录是否真的调了退出。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:uiv2/src/app_router.dart';
import 'package:uiv2/src/components/now_playing.dart';
import 'package:uiv2/src/design/theme.dart';
import 'package:uiv2/src/pages/profile_page.dart';
import 'package:uiv2/src/pages/settings_page.dart';
import 'package:uiv2/src/providers/providers.dart';
import 'package:uiv2/src/router.dart';

/// 假播放缓存（与 route_keepalive_test 同一套假件）
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
  Future<void> cacheAfterPlay(
    Song song,
    String url, {
    Map<String, String>? headers,
  }) async {}
  @override
  Future<int> sizeOnDisk() async => 0;
  @override
  Future<void> clear() async {}
  @override
  Stream<void> get changes => const Stream.empty();
}

/// 假播放器
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
  Future<void> prepareAt(
    int index, {
    Duration position = Duration.zero,
  }) async {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('假播放器未实现该成员');
}

void main() {
  late ProviderContainer container;
  // SystemNavigator.pop 是否真的被调用（= App 真的被退出了）
  var systemExitRequested = false;

  setUp(() async {
    systemExitRequested = false;
    final db = InMemoryDatabaseProvider();
    await db.initialize();
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        playerProvider.overrideWithValue(_FakePlayer()),
        sourceManagerProvider.overrideWithValue(SourceManager()),
        audioCacheProvider.overrideWithValue(_FakeCache()),
        recentPlaysServiceProvider.overrideWithValue(
          RecentPlaysService(db.recentPlaysDao),
        ),
      ],
    );
    // mock 平台通道：SystemNavigator.pop 在测试里不会真的退出，
    // 只记录调用，供断言「按两次才退出 / 播放页开启时不退出」
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemNavigator.pop') systemExitRequested = true;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    container.dispose();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(444, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: container.read(appRouterProvider),
          theme: UiV2DesignTheme.dark(),
          builder: (context, c) =>
              c == null ? const SizedBox() : UiV2Scope(child: c),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('一级页按返回：第一次只提示，两秒内第二次才退出', (tester) async {
    await pumpApp(tester);

    // 第一次系统返回：App 不能退，给「再按一次」提示
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('再按一次返回键退出'), findsOneWidget, reason: '第一次返回应该提示而不是直接退出');
    expect(systemExitRequested, isFalse, reason: '第一次返回不能退出 App');

    // 两秒内第二次系统返回：真的退出（SystemNavigator.pop 被调用）
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    expect(systemExitRequested, isTrue, reason: '两秒内第二次返回才退出');

    // 消化提示条的 2.2s 自动消失定时器：pumpAndSettle 不会为「仅 pending 的
    // Timer」推进时钟（它不排帧），必须显式 pump 越过去
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('二级页按返回：出栈回上一页，不触发退出', (tester) async {
    await pumpApp(tester);

    container.read(navProvider.notifier).go('settings');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SettingsPage), findsOneWidget);

    // 系统返回：出栈二级页，回到「我的」
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      container.read(navProvider).current.name,
      'profile',
      reason: '二级页系统返回应回上一页',
    );
    expect(find.byType(SettingsPage), findsNothing);
    expect(systemExitRequested, isFalse, reason: '出栈二级页不能退出 App');
  });

  testWidgets('移动端二级一级页（我喜欢的音乐）按返回：退到上一级', (tester) async {
    await pumpApp(tester);

    container.read(navProvider.notifier).go('liked');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(navProvider).current.name, 'liked');

    // liked 是一级分支（分支 Navigator 没得弹）→ 退到上一级「我的」，
    // 与顶栏返回键同一条 NavNotifier.back 路径
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      container.read(navProvider).current.name,
      'profile',
      reason: '移动端二级一级页系统返回应退到上一级而不是退出',
    );
    expect(systemExitRequested, isFalse);
  });

  testWidgets('沉浸播放页开着按返回：先收起播放页，不退出', (tester) async {
    await pumpApp(tester);

    container.read(nowPlayingProvider.notifier).open();
    // 覆盖层的展开动画由 postFrame 回调驱动，用 pumpAndSettle 等它完整打开
    await tester.pumpAndSettle();
    expect(find.byType(UiV2NowPlayingScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(container.read(nowPlayingProvider), isFalse, reason: '返回键应先收起沉浸播放页');
    expect(find.byType(UiV2NowPlayingScreen), findsNothing);
    expect(systemExitRequested, isFalse, reason: '收起播放页不能退出 App');
    expect(
      container.read(navProvider).current.name,
      'home',
      reason: '收起播放页不改导航位置',
    );
  });
}
