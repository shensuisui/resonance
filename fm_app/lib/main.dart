/// fm 音乐播放器 — 壳工程入口
///
/// 职责：
/// 1. 初始化 SQLite 数据库（SqfliteDatabaseProvider）
/// 2. 创建 PlayerImpl 播放器
/// 3. 从 assets/rules/ 加载规则源
/// 4. 注册本地源 + 规则源到 SourceManager
/// 5. 通过 ProviderScope.overrides 注入服务到 UI 层
///
/// 壳工程不写业务逻辑，只做组装。

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import 'package:crawler/crawler.dart';
import 'package:db/db.dart';
import 'package:player/player.dart';
import 'package:ui/ui.dart';

late DatabaseProvider gDatabaseProvider;
late SourceManager gSourceManager;
late RecentPlaysService gRecentPlaysService;
late Player gPlayer;
late DownloadManager gDownloadManager;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. 初始化 SQLite 数据库
  gDatabaseProvider = SqfliteDatabaseProvider();
  await gDatabaseProvider.initialize();

  // 2. 创建播放器、最近播放服务和下载管理器
  gPlayer = PlayerImpl();
  gRecentPlaysService =
      RecentPlaysService(gDatabaseProvider.recentPlaysDao);
  gDownloadManager = DownloadManagerImpl(songDao: gDatabaseProvider.songDao);

  // 3. 创建 SourceManager 并注册源
  gSourceManager = SourceManager();
  gSourceManager.registerSource(LocalScanSource(gDatabaseProvider.songDao,
      gDatabaseProvider.settingsDao, const AudiotagsMetadataReader()));
  gSourceManager.registerSource(
      LocalCustomSource(gDatabaseProvider.songDao));
  gSourceManager.registerSource(
      FavoriteSource(gDatabaseProvider.favoritesDao, gSourceManager));
  gSourceManager.setSourceEnabled('local_scan', true);
  gSourceManager.setSourceEnabled('local_custom', true);
  gSourceManager.setSourceEnabled('favorite', true);

  // 4. 从 assets/rules/ 加载规则源
  await _loadRuleSources();

  // 5. 启动应用，通过 ProviderScope 注入服务
  runApp(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(gDatabaseProvider),
      sourceManagerProvider.overrideWithValue(gSourceManager),
      recentPlaysServiceProvider.overrideWithValue(gRecentPlaysService),
      playerProvider.overrideWithValue(gPlayer),
      downloadManagerProvider.overrideWithValue(gDownloadManager),
    ],
    child: const FmApp(),
  ));
}

/// 从 assets/rules/ 加载所有 .json 规则文件
Future<void> _loadRuleSources() async {
  try {
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final manifest = jsonDecode(manifestContent) as Map<String, dynamic>;
    final ruleFiles = manifest.keys
        .where((key) =>
            key.startsWith('assets/rules/') && key.endsWith('.json'))
        .toList();

    for (final path in ruleFiles) {
      try {
        final jsonStr = await rootBundle.loadString(path);
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        final config = RuleConfig.fromJson(json);
        final source = RuleBasedMusicSource(config);
        gSourceManager.registerSource(source);
        gSourceManager.setSourceEnabled(config.source.id, true);
      } catch (e) {
        debugPrint('加载规则源失败: $path — $e');
      }
    }
  } catch (e) {
    debugPrint('加载规则源目录失败: $e');
  }
}

/// 应用根 Widget
class FmApp extends ConsumerWidget {
  const FmApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'FM 音乐',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: const AppShell(),
    );
  }
}
