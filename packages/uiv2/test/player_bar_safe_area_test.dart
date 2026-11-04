/// 播放栏底部安全区回归测试（Issue #7）。
///
/// 模拟 Android 24px 底部手势区域，验证一级页只由 TabBar 消费安全区，
/// 没有 TabBar 的二级页仍由播放栏消费；无安全区平台布局保持原样。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:uiv2/src/app_router.dart';
import 'package:uiv2/src/components/player_bar.dart';
import 'package:uiv2/src/components/shell_parts.dart';
import 'package:uiv2/src/design/theme.dart';
import 'package:uiv2/src/providers/providers.dart';
import 'package:uiv2/src/router.dart';

/// 空播放器：测试只构建界面，不触发真实音频或平台通道。
class _FakePlayer implements Player {
  @override
  Stream<PlayerState> get stateStream => const Stream.empty();
  @override
  Stream<int> get positionStream => const Stream.empty();
  @override
  Stream<int> get durationStream => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 空缓存：应用外壳启动恢复需要 AudioCache，但不访问磁盘。
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

/// 独立播放栏宿主，统一注入与真实 App 相同的主题和底部安全区。
Widget _host(Widget child, List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: UiV2DesignTheme.dark(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(padding: const EdgeInsets.only(bottom: 24)),
      child: child == null ? const SizedBox() : UiV2Scope(child: child),
    ),
    home: Scaffold(body: child),
  ),
);

List<Override> _overrides(InMemoryDatabaseProvider db) => [
  appDatabaseProvider.overrideWithValue(db),
  playerProvider.overrideWithValue(_FakePlayer()),
  sourceManagerProvider.overrideWithValue(SourceManager()),
];

/// 播放栏背景容器的 padding，直接锁定视觉间距而非只测组件总高度。
EdgeInsets _playerPadding(WidgetTester tester) {
  final container = tester
      .widgetList<Container>(
        find.descendant(
          of: find.byType(UiV2PlayerBar),
          matching: find.byType(Container),
        ),
      )
      .firstWhere((widget) => widget.padding is EdgeInsets);
  return container.padding! as EdgeInsets;
}

void main() {
  testWidgets('一级页播放栏不重复添加底部安全区，上下间距一致', (tester) async {
    final db = InMemoryDatabaseProvider();
    await db.initialize();
    await tester.pumpWidget(
      _host(
        const UiV2PlayerBar(
          wide: false,
          tablet: false,
          applyBottomSafeArea: false,
        ),
        _overrides(db),
      ),
    );

    final padding = _playerPadding(tester);
    expect(padding.top, 8);
    expect(padding.bottom, 8);
  });

  testWidgets('独立播放栏保留底部安全区，无安全区时布局不变', (tester) async {
    final db = InMemoryDatabaseProvider();
    await db.initialize();
    await tester.pumpWidget(
      _host(const UiV2PlayerBar(wide: false, tablet: false), _overrides(db)),
    );
    expect(_playerPadding(tester).bottom, 32);

    await tester.pumpWidget(
      _host(
        const MediaQuery(
          data: MediaQueryData(),
          child: UiV2PlayerBar(wide: false, tablet: false),
        ),
        _overrides(db),
      ),
    );
    expect(_playerPadding(tester).bottom, 8);
  });

  testWidgets('AppShell 仅在一级页关闭播放栏安全区', (tester) async {
    tester.view.physicalSize = const Size(444, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = InMemoryDatabaseProvider();
    await db.initialize();
    final container = ProviderContainer(
      overrides: [
        ..._overrides(db),
        audioCacheProvider.overrideWithValue(_FakeCache()),
        recentPlaysServiceProvider.overrideWithValue(
          RecentPlaysService(db.recentPlaysDao),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: container.read(appRouterProvider),
          theme: UiV2DesignTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(padding: const EdgeInsets.only(bottom: 24)),
            child: child == null ? const SizedBox() : UiV2Scope(child: child),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    UiV2PlayerBar playerBar() => tester.widget(find.byType(UiV2PlayerBar));
    expect(playerBar().applyBottomSafeArea, isFalse);
    // 一级页只有最底部 TabBar 消费安全区：4px 基础间距 + 24px 手势区。
    final tabBarContainer = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(UiV2TabBar),
            matching: find.byType(Container),
          ),
        )
        .firstWhere((widget) => widget.padding is EdgeInsets);
    expect(tabBarContainer.padding, const EdgeInsets.fromLTRB(6, 4, 6, 28));

    container.read(navProvider.notifier).go('settings');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(playerBar().applyBottomSafeArea, isTrue);
  });
}
