// 真实 WebView 集成测试 — 全部插件
// 从 MusicFree 插件列表下载所有插件，逐个测试搜索流程
import 'dart:convert';

import 'package:core/core.dart';
import 'package:crawler/crawler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 插件列表 URL
  const pluginListUrl =
      'https://fastly.jsdelivr.net/gh/Huibq/keep-alive/Music_Free/myPlugins.json';

  /// 下载插件列表 JSON，返回 [{name, url}, ...]
  Future<List<Map<String, String>>> downloadPluginList() async {
    final httpClient = HttpClient();
    final response = await httpClient.get(pluginListUrl, responseType: 'text');
    httpClient.dispose();

    final decoded = jsonDecode(response.rawData);
    // JSON 可能是数组或对象（含 plugins 键）
    final List<dynamic> list;
    if (decoded is List) {
      list = decoded;
    } else if (decoded is Map && decoded['plugins'] is List) {
      list = decoded['plugins'] as List;
    } else {
      list = [];
    }

    return list
        .map((e) => {
              'name': (e is Map ? (e['name'] ?? '未知') : '未知').toString(),
              'url': (e is Map ? (e['url'] ?? '') : '').toString(),
            })
        .where((e) => e['url']!.isNotEmpty)
        .toList();
  }

  /// 下载插件 JS 内容
  Future<String> downloadPluginJs(String url) async {
    final httpClient = HttpClient();
    final response = await httpClient.get(url, responseType: 'text');
    httpClient.dispose();
    return response.rawData;
  }

  /// 从 JS 内容提取插件名称
  String extractPluginName(String jsContent) {
    final nameMatch =
        RegExp(r"""(?:name|platform)\s*[:=]\s*["']([^"']+)["']""")
            .firstMatch(jsContent);
    return nameMatch?.group(1) ?? '未知插件';
  }

  group('真实 WebView — 全部插件搜索测试', () {
    testWidgets('下载插件列表', (tester) async {
      print('📋 下载插件列表...');
      final plugins = await downloadPluginList();
      print('   ✅ 共 ${plugins.length} 个插件');
      for (final p in plugins) {
        print('   - ${p['name']}: ${p['url']}');
      }
      expect(plugins.length, greaterThan(0));
    });

    testWidgets('逐个插件搜索周杰伦', (tester) async {
      // 1. 下载插件列表
      print('📋 下载插件列表...');
      final plugins = await downloadPluginList();
      print('   ✅ 共 ${plugins.length} 个插件');

      final results = <String, int>{};

      for (final plugin in plugins) {
        final name = plugin['name']!;
        final url = plugin['url']!;

        print('\n════════════════════════════════════');
        print('🎵 测试插件: $name');
        print('📥 下载插件 JS...');

        String jsContent;
        try {
          jsContent = await downloadPluginJs(url).timeout(
            const Duration(seconds: 15),
            onTimeout: () => '',
          );
        } catch (e) {
          print('   ❌ 下载失败: $e');
          results[name] = -1;
          continue;
        }

        if (jsContent.isEmpty || jsContent.length < 100) {
          print('   ❌ 插件内容无效 (${jsContent.length} bytes)');
          results[name] = -1;
          continue;
        }
        print('   ✅ 下载成功 (${jsContent.length} bytes)');

        // 2. 初始化 WebView
        final runtime = JsRuntime();
        try {
          await runtime.init();
          print('   🔧 WebView 就绪');

          // 3. 加载插件
          await runtime.loadPlugin(jsContent);
          final loaded = await runtime.isPluginLoaded();
          if (!loaded) {
            print('   ❌ 插件加载失败');
            results[name] = -1;
            continue;
          }
          print('   📦 插件已加载');

          // 4. 检查 search 函数
          final hasSearch = await runtime.hasFunction('search');
          if (!hasSearch) {
            print('   ❌ 无 search 函数');
            results[name] = -1;
            continue;
          }

          // 5. 搜索周杰伦
          print('   🔍 搜索: 周杰伦');
          final pluginName = extractPluginName(jsContent);
          final source = JsPluginSource(runtime, pluginName);

          final result = await source
              .search(keyword: '周杰伦', page: 1)
              .timeout(const Duration(seconds: 30));

          print('   ✅ 搜索结果: ${result.songs.length} 首');
          for (final song in result.songs.take(3)) {
            print('      - ${song.title} - ${song.artist}');
          }

          results[name] = result.songs.length;

          // 6. 获取播放 URL（如果有结果）
          if (result.songs.isNotEmpty) {
            final firstSong = result.songs.first;
            print('   🎵 获取播放 URL: ${firstSong.title}');
            final playUrl = await source
                .getSongUrl(firstSong.id)
                .timeout(const Duration(seconds: 15), onTimeout: () => '');
            print('   播放 URL: ${playUrl.isEmpty ? "(空)" : playUrl}');
          }
        } catch (e) {
          print('   ❌ 测试失败: $e');
          results[name] = -1;
        } finally {
          await runtime.dispose();
        }
      }

      // 7. 汇总结果
      print('\n════════════════════════════════════');
      print('📊 测试结果汇总:');
      for (final entry in results.entries) {
        final status = entry.value > 0
            ? '✅ ${entry.value} 首'
            : entry.value == 0
                ? '⚠️  0 首'
                : '❌ 失败';
        print('   ${entry.key}: $status');
      }

      // 至少一个插件搜索成功
      final successCount = results.values.where((c) => c > 0).length;
      expect(successCount, greaterThan(0),
          reason: '至少一个插件应搜索成功');
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}