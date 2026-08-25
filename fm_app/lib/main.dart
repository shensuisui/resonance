/// fm 音乐播放器 — 壳工程入口
///
/// 职责：
/// 1. 初始化 SQLite 数据库（SqfliteDatabaseProvider）
/// 2. 从 assets/rules/ 加载规则源
/// 3. 注册本地源 + 规则源到 SourceManager
/// 4. 启动 UI（S2 阶段替换为 Riverpod + 完整页面）
///
/// 壳工程不写业务逻辑，只做组装。

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:core/core.dart';
import 'package:crawler/crawler.dart';
import 'package:db/db.dart';

late DatabaseProvider gDatabaseProvider;
late SourceManager gSourceManager;
late RecentPlaysService gRecentPlaysService;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. 初始化 SQLite 数据库
  gDatabaseProvider = SqfliteDatabaseProvider();
  await gDatabaseProvider.initialize();

  // 2. 初始化最近播放服务
  gRecentPlaysService =
      RecentPlaysService(gDatabaseProvider.recentPlaysDao);

  // 3. 创建 SourceManager
  gSourceManager = SourceManager();

  // 4. 注册本地源
  gSourceManager.registerSource(LocalCustomSource(gDatabaseProvider.songDao));
  gSourceManager.registerSource(
      FavoriteSource(gDatabaseProvider.favoritesDao, gSourceManager));
  gSourceManager.setSourceEnabled('local_custom', true);
  gSourceManager.setSourceEnabled('favorite', true);

  // 5. 从 assets/rules/ 加载规则源
  await _loadRuleSources();

  runApp(const FmApp());
}

/// 从 assets/rules/ 加载所有 .json 规则文件
Future<void> _loadRuleSources() async {
  try {
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final manifest = jsonDecode(manifestContent) as Map<String, dynamic>;
    final ruleFiles = manifest.keys
        .where((key) => key.startsWith('assets/rules/') && key.endsWith('.json'))
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

/// 应用根 Widget（S2 阶段替换为 Riverpod + 完整 UI）
class FmApp extends StatelessWidget {
  const FmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FM 音乐',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const _PlaceholderPage(),
    );
  }
}

/// 占位页面（S2 替换为搜索页）
class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage();

  @override
  Widget build(BuildContext context) {
    final sources = gSourceManager.getAllSources();
    return Scaffold(
      appBar: AppBar(title: const Text('FM 音乐')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('数据库已初始化 ✅'),
            const SizedBox(height: 16),
            Text('已注册源: ${sources.length} 个'),
            const SizedBox(height: 16),
            ...sources.map((s) => Text('• ${s.sourceInfo.name} (${s.sourceInfo.id})')),
          ],
        ),
      ),
    );
  }
}
