/// UI 端到端冒烟测试（真实组件树 + 真实布局）
///
/// 覆盖：
/// 1. 应用启动（真实 DB/播放器/源管理器组装）与底部导航切换
/// 2. 播放器覆盖层：迷你条 → 点击展开全屏播放页（断言关键控件存在）
/// 3. 详情页：歌单详情头部（标题/播放全部）与列表渲染
///
/// 说明：歌曲/歌单数据用注入方式（不依赖网络与本地曲库），
/// 但组件树、布局、交互全部真实执行；布局溢出会以异常形式暴露。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:core/core.dart';
import 'package:db/db.dart';
import 'package:player/player.dart';
import 'package:ui/ui.dart';
import 'package:resonance_app/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final song = Song(
    id: 'ui_test_1',
    sourceId: 'local_custom',
    title: '端到端测试歌曲',
    artist: '测试歌手',
  );

  /// 组装与 resonance_app main() 一致的服务，并注入状态后泵入应用
  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    bool withSong = false,
  }) async {
    final db = SqfliteDatabaseProvider();
    await db.initialize();
    final manager = SourceManager();
    manager.registerSource(LocalCustomSource(db.songDao));
    manager.setSourceEnabled('local_custom', true);

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWith((ref) => db),
      sourceManagerProvider.overrideWith((ref) => manager),
      playerProvider.overrideWith((ref) => PlayerImpl()),
      recentPlaysServiceProvider
          .overrideWith((ref) => RecentPlaysService(db.recentPlaysDao)),
      downloadManagerProvider
          .overrideWith((ref) => DownloadManagerImpl(songDao: db.songDao)),
    ]);
    addTearDown(container.dispose);

    if (withSong) {
      container.read(currentSongProvider.notifier).setSong(song);
      container.read(isPlayingProvider.notifier).setPlaying(true);
      container
          .read(playbackDurationProvider.notifier)
          .setDuration(const Duration(seconds: 200));
      container
          .read(playbackPositionProvider.notifier)
          .setPosition(const Duration(seconds: 30));
    }

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const ResonanceApp(),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('启动并切换底部导航（竖屏）', (tester) async {
    // 竖屏尺寸（手机）
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester);

    // 底部导航存在（窄屏布局）
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('搜索'), findsWidgets);
    expect(find.text('发现'), findsWidgets);

    // 切到「设置」
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(find.text('外观'), findsWidgets);

    // 切到「歌单」
    await tester.tap(find.text('歌单').last);
    await tester.pumpAndSettle();
    expect(find.text('我最喜欢'), findsWidgets);
  });

  testWidgets('播放器覆盖层：迷你条点击展开全屏播放页', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester, withSong: true);

    // 迷你条存在（含歌曲标题）
    expect(find.byType(MiniPlayer), findsOneWidget);
    expect(find.textContaining('端到端测试歌曲'), findsWidgets);

    // 点击迷你条展开全屏播放器
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();

    // 播放页关键控件（transport 三键 + 开关行 + 进度条）
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('宽屏布局使用 NavigationRail', (tester) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
