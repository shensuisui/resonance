// 真实 WebView 集成测试
// 使用 integration_test 在真实 Windows 窗口中运行 HeadlessInAppWebView
// 验证 MusicFree JS 插件从下载到搜索到获取播放 URL 的完整流程
import 'package:crawler/crawler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 插件下载 URL
  const pluginUrl =
      'https://fastly.jsdelivr.net/gh/Huibq/keep-alive/Music_Free/xiaoqiu.js';

  /// 下载插件 JS 内容
  Future<String> downloadPluginJs() async {
    final httpClient = HttpClient();
    final response = await httpClient.get(pluginUrl, responseType: 'text');
    httpClient.dispose();
    return response.rawData;
  }

  group('真实 WebView — JsRuntime', () {
    testWidgets('WebView 初始化', (tester) async {
      final runtime = JsRuntime();
      await runtime.init();
      expect(runtime.isInitialized, isTrue);
      await runtime.dispose();
    });

    testWidgets('加载插件并验证结构', (tester) async {
      // 1. 下载真实插件
      final jsContent = await downloadPluginJs();
      expect(jsContent.length, greaterThan(1000), reason: '插件内容过短');

      // 2. 初始化 WebView
      final runtime = JsRuntime();
      await runtime.init();

      // 3. 加载插件
      await runtime.loadPlugin(jsContent);

      // 4. 验证插件已加载
      final loaded = await runtime.isPluginLoaded();
      expect(loaded, isTrue, reason: '插件未加载');

      // 5. 验证关键函数存在
      expect(await runtime.hasFunction('search'), isTrue);
      expect(await runtime.hasFunction('getMediaSource'), isTrue);

      await runtime.dispose();
    });
  });

  group('真实 WebView — 完整流程', () {
    testWidgets('下载插件 → 加载 → 搜索 → 获取 URL', (tester) async {
      // 1. 下载真实插件
      print('📥 下载插件...');
      final jsContent = await downloadPluginJs();
      print('   ✅ 下载成功 (${jsContent.length} bytes)');

      // 2. 初始化 WebView 并加载插件
      print('🔧 初始化 WebView...');
      final runtime = JsRuntime();
      await runtime.init();
      print('   ✅ WebView 就绪');

      print('📦 加载插件 JS...');
      await runtime.loadPlugin(jsContent);
      expect(await runtime.isPluginLoaded(), isTrue);
      print('   ✅ 插件已加载');

      // 3. 提取插件名称
      final nameMatch = RegExp(r"""(?:name|platform)\s*[:=]\s*["']([^"']+)["']""")
          .firstMatch(jsContent);
      final pluginName = nameMatch?.group(1) ?? '未知插件';
      print('   插件名称: $pluginName');

      // 4. 搜索周杰伦（直接调用 runtime 获取原始结果）
      print('🔍 搜索: 周杰伦');
      final rawResult = await runtime.callPluginFunction(
        "search('周杰伦', 1, 'music')",
      ).timeout(const Duration(seconds: 30));
      final raw = rawResult ?? '';
      print('   原始结果长度: ${raw.length}');
      print('   原始结果前200字符: ${raw.substring(0, raw.length.clamp(0, 200))}');

      // 5. 通过 JsPluginSource 解析结果
      final source = JsPluginSource(runtime, pluginName);
      final result = await source
          .search(keyword: '周杰伦', page: 1)
          .timeout(const Duration(seconds: 30));

      print('   搜索结果: ${result.songs.length} 首');
      for (final song in result.songs.take(5)) {
        print('   - ${song.title} - ${song.artist}');
      }

      // 6. 获取播放 URL
      if (result.songs.isNotEmpty) {
        final firstSong = result.songs.first;
        print('🎵 获取播放 URL: ${firstSong.title}');
        final url = await source
            .getSongUrl(firstSong.id)
            .timeout(const Duration(seconds: 30));
        print('   播放 URL: $url');
        expect(url, isA<String>());
      } else {
        print('   ⚠️ 搜索无结果，跳过获取 URL');
      }

      await runtime.dispose();
      print('🎉 完整流程测试完成');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}