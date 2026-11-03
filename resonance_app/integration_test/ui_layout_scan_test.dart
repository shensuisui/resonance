/// UI 布局扫描测试（多尺寸 × 多页面）
///
/// 目的：一次性覆盖全部页面在【竖屏窄窗 / 宽屏横窗】两种布局下的
/// 渲染结果，输出关键元素的真实尺寸/位置，并检查布局溢出。
///
/// 用法：flutter test integration_test/ui_layout_scan_test.dart -d windows
/// 输出：[scan] 前缀行即为尺寸报告。
///
/// 说明：为避免无限动画（ShimmerBox / EQ）导致 pumpAndSettle 超时，
/// 统一用固定时长 pump。
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:core/core.dart';
import 'package:db/db.dart';
import 'package:player/player.dart';
import 'package:ui/ui.dart';
import 'package:resonance_app/main.dart';

/// 用例内 DB 文件序号（保证唯一路径）
int _dbSeq = 0;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final song = Song(
    id: 'scan_song_1',
    sourceId: 'local_custom',
    title: '扫描测试歌曲（很长的标题用于测试跑马灯与换行）',
    artist: '测试歌手',
    album: '测试专辑',
    duration: 215,
  );

  /// 输出元素尺寸报告
  void report(WidgetTester tester, String label, Finder finder) {
    if (finder.evaluate().isEmpty) {
      debugPrint('[scan] $label: <NOT FOUND>');
      return;
    }
    final r = tester.getRect(finder.first);
    debugPrint(
        '[scan] $label: ${r.width.toStringAsFixed(1)}x${r.height.toStringAsFixed(1)} @(${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)})');
  }

  /// 检查并报告溢出/异常
  void checkOverflow(String page) {
    final ex = TestWidgetsFlutterBinding.instance.takeException();
    if (ex != null) {
      debugPrint('[scan][OVERFLOW] $page: $ex');
    } else {
      debugPrint('[scan][OK] $page: no exception');
    }
  }

  /// 组装应用（真实服务 + 可选注入歌曲/歌单）
  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    required Size size,
    bool withSong = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 每个用例独立 DB 文件，避免跨用例主键冲突/状态污染
    _dbSeq++;
    final dbPath =
        '${Directory.systemTemp.path}\\resonance_scan_${DateTime.now().microsecondsSinceEpoch}_$_dbSeq.db';
    final db = SqfliteDatabaseProvider.withHelper(
      DatabaseHelper(customDbPath: dbPath),
    );
    await db.initialize();
    addTearDown(() async {
      await db.close();
      final f = File(dbPath);
      if (f.existsSync()) f.deleteSync();
    });
    final manager = SourceManager();
    manager.registerSource(LocalCustomSource(db.songDao));
    manager.setSourceEnabled('local_custom', true);

    // 写入一首歌 + 一个歌单（供详情页/播放页使用）
    await db.songDao.insertSong(song);
    final now = DateTime.now();
    await db.playlistDao.insertPlaylist(Playlist(
      id: 'scan_pl',
      name: '扫描测试歌单',
      songKeys: [song.globalKey],
      createdTime: now,
      modifiedTime: now,
    ));

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
          .setDuration(const Duration(seconds: 215));
      container
          .read(playbackPositionProvider.notifier)
          .setPosition(const Duration(seconds: 42));
      container.read(playQueueProvider.notifier).setQueue([song]);
    }

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const ResonanceApp(),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    return container;
  }

  /// 按名称点击导航项（竖屏 NavigationBar / 宽屏 NavigationRail 通用）
  Future<void> navTo(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).first);
    await tester.pump(const Duration(milliseconds: 500));
  }

  // ==================== 竖屏 400x900（底部导航） ====================

  group('竖屏 400x900', () {
    const size = Size(400, 900);

    testWidgets('搜索页（空闲态）', (tester) async {
      await pumpApp(tester, size: size);
      report(tester, '竖屏/底部导航栏', find.byType(NavigationBar));
      report(tester, '竖屏/搜索输入框', find.byType(TextField));
      checkOverflow('竖屏/搜索页');
    });

    testWidgets('发现页（最近播放 + 快捷入口 + 歌单网格）', (tester) async {
      await pumpApp(tester, size: size);
      await navTo(tester, '发现');
      await tester.pump(const Duration(seconds: 2));
      report(tester, '竖屏/发现/AppBar', find.byType(AppBar));
      report(tester, '竖屏/发现/音乐源管理入口', find.text('音乐源管理'));
      checkOverflow('竖屏/发现页');
    });

    testWidgets('歌单列表页（含我最喜欢 + 测试歌单）', (tester) async {
      await pumpApp(tester, size: size);
      await navTo(tester, '歌单');
      await tester.pump(const Duration(milliseconds: 600));
      report(tester, '竖屏/歌单/我最喜欢项', find.text('我最喜欢'));
      report(tester, '竖屏/歌单/测试歌单项', find.text('扫描测试歌单'));
      checkOverflow('竖屏/歌单列表');
    });

    testWidgets('设置页', (tester) async {
      await pumpApp(tester, size: size);
      await navTo(tester, '设置');
      await tester.pump(const Duration(milliseconds: 600));
      report(tester, '竖屏/设置/外观项', find.text('外观'));
      checkOverflow('竖屏/设置页');
    });

    testWidgets('播放页（迷你条 → 展开全屏）', (tester) async {
      await pumpApp(tester, size: size, withSong: true);
      report(tester, '竖屏/迷你条', find.byType(MiniPlayer));
      await tester.tap(find.byType(MiniPlayer));
      await tester.pump(const Duration(milliseconds: 800));
      report(tester, '竖屏/播放页', find.byType(PlayerPage));
      report(tester, '竖屏/播放页/封面区', find.byType(ScrollableText));
      report(tester, '竖屏/播放页/进度条', find.byType(Slider));
      report(tester, '竖屏/播放页/上一首', find.byIcon(Icons.skip_previous_rounded));
      // 注意：playerStreamBinding 会把 isPlaying 同步为真实播放器状态，
      // 测试环境无真实播放 → 渲染 play_arrow；两种图标都算通过
      final hasPlay = find.byIcon(Icons.play_arrow_rounded).evaluate().isNotEmpty;
      final hasPause = find.byIcon(Icons.pause_rounded).evaluate().isNotEmpty;
      debugPrint('[scan] 竖屏/播放页/播放键: '
          '${hasPlay ? "play_arrow" : ""}${hasPause ? "pause" : ""}'
          '${(!hasPlay && !hasPause) ? "<NOT FOUND>" : ""}');
      expect(hasPlay || hasPause, isTrue, reason: '播放/暂停按钮应存在');
      report(tester, '竖屏/播放页/随机', find.byIcon(Icons.shuffle_rounded));
      report(tester, '竖屏/播放页/收藏', find.byIcon(Icons.favorite_border_rounded));
      checkOverflow('竖屏/播放页');
    });

    testWidgets('播放页歌词模式（竖屏）', (tester) async {
      await pumpApp(tester, size: size, withSong: true);
      await tester.tap(find.byType(MiniPlayer));
      await tester.pump(const Duration(milliseconds: 800));
      // 点歌词按钮切到歌词视图
      await tester.tap(find.byIcon(Icons.lyrics_outlined));
      await tester.pump(const Duration(milliseconds: 600));
      report(tester, '竖屏/播放页/歌词视图', find.byType(LyricsView));
      checkOverflow('竖屏/播放页(歌词)');
    });

    testWidgets('专辑页（竖屏，加载/空态渲染不崩溃）', (tester) async {
      final container = await pumpApp(tester, size: size);
      // 直接以专辑页为根（源管理器已注入，搜索无结果时走空态）
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AlbumPage(albumName: '测试专辑', artistName: '测试歌手'),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 1200));
      report(tester, '竖屏/专辑页', find.byType(AlbumPage));
      checkOverflow('竖屏/专辑页');
    });

    testWidgets('歌手页（空态 + 头部对齐）', (tester) async {
      final container = await pumpApp(tester, size: size);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ArtistPage(artistName: '不存在的歌手'),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 1200));
      report(tester, '竖屏/歌手页/AppBar', find.byType(AppBar));
      report(tester, '竖屏/歌手页/空态', find.byType(EmptyState));
      checkOverflow('竖屏/歌手页');
    });

    testWidgets('队列 Sheet（空队列空态）', (tester) async {
      // 复用 pumpApp 的 container（QueueSheet 依赖 playQueueProvider 等）
      final container = await pumpApp(tester, size: size);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: QueueSheet())),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      report(tester, '竖屏/队列Sheet/空态', find.byType(EmptyState));
      checkOverflow('竖屏/队列 Sheet');
    });

    testWidgets('专辑页空态带 AppBar（三态返回入口回归）', (tester) async {
      final container = await pumpApp(tester, size: size);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AlbumPage(albumName: '不存在的专辑', artistName: '不存在的歌手'),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 1200));
      // 修复点：三态（加载/错误/空）此前没有 AppBar，导致无返回按钮
      report(tester, '竖屏/专辑页空态/AppBar', find.byType(AppBar));
      report(tester, '竖屏/专辑页空态/空态组件', find.byType(EmptyState));
      checkOverflow('竖屏/专辑页空态');
    });
  });

  // ==================== 宽屏 1200x700（NavigationRail） ====================

  group('宽屏 1200x700', () {
    const size = Size(1200, 700);

    testWidgets('搜索页（宽屏）', (tester) async {
      await pumpApp(tester, size: size);
      report(tester, '宽屏/侧栏', find.byType(NavigationRail));
      checkOverflow('宽屏/搜索页');
    });

    testWidgets('发现页（宽屏）', (tester) async {
      await pumpApp(tester, size: size);
      await navTo(tester, '发现');
      await tester.pump(const Duration(seconds: 2));
      report(tester, '宽屏/发现/音乐源管理入口', find.text('音乐源管理'));
      checkOverflow('宽屏/发现页');
    });

    testWidgets('歌单详情页（宽屏，左面板 + 右列表）', (tester) async {
      await pumpApp(tester, size: size);
      await navTo(tester, '歌单');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('扫描测试歌单'));
      await tester.pump(const Duration(milliseconds: 900));
      report(tester, '宽屏/详情/播放全部', find.text('播放全部').first);
      report(tester, '宽屏/详情/歌曲卡片', find.byType(SongTile));
      report(tester, '宽屏/详情/歌单名', find.text('扫描测试歌单').first);
      checkOverflow('宽屏/歌单详情');
    });

    testWidgets('播放页（宽屏）', (tester) async {
      await pumpApp(tester, size: size, withSong: true);
      report(tester, '宽屏/迷你条', find.byType(MiniPlayer));
      await tester.tap(find.byType(MiniPlayer));
      await tester.pump(const Duration(milliseconds: 800));
      report(tester, '宽屏/播放页', find.byType(PlayerPage));
      report(tester, '宽屏/播放页/进度条', find.byType(Slider));
      checkOverflow('宽屏/播放页');
    });
  });
}
