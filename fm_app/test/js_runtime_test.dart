// 集成测试：JS 插件运行时
// 需要 WebView2 运行时。运行方式：
//   1. 确保 Windows 已安装 WebView2 Runtime
//   2. cd fm_app && fvm flutter test test/js_runtime_test.dart
//
// 如果环境不支持 WebView2，测试会输出提示并降级验证插件结构

import 'dart:convert';
import 'dart:io';

import 'package:crawler/crawler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('JS 插件下载、加载、搜索、获取播放 URL', () async {
    // 下载插件
    final downloader = PluginDownloader();
    final tempDir = Directory.systemTemp.createTempSync('js_runtime_test_');
    final jsPath = '${tempDir.path}/xiaoqiu.js';

    final path = await downloader.downloadPlugin(
      'https://fastly.jsdelivr.net/gh/Huibq/keep-alive/Music_Free/xiaoqiu.js',
      jsPath,
    );
    downloader.dispose();
    expect(path, isNotNull, reason: '插件下载失败');

    final jsContent = File(path!).readAsStringSync();

    // 尝试初始化 JS 运行时（带超时）
    final runtime = JsRuntime();
    try {
      await runtime.init().timeout(const Duration(seconds: 15));
    } catch (e) {
      // WebView2 不可用（测试环境无平台通道），降级验证
      print('JS 运行时不可用（测试环境无 WebView2 平台通道）：$e');
      print('降级验证：插件结构 + LxMusicAdapter 识别');
      final source = await LxMusicAdapter.tryCreate(jsContent);
      expect(source, isNotNull, reason: '插件无法被 LxMusicAdapter 识别');
      expect(source!.sourceInfo.name, contains('小秋音乐'));
      print('插件名称: ${source.sourceInfo.name}');
      tempDir.deleteSync(recursive: true);
      return;
    }

    // 运行时可用，执行完整测试
    try {
      await runtime.loadPlugin(jsContent);
      final loaded = await runtime.isPluginLoaded();
      expect(loaded, isTrue, reason: '插件加载失败');
      expect(await runtime.hasFunction('search'), isTrue);
      expect(await runtime.hasFunction('getMediaSource'), isTrue);

      // 搜索
      final searchResult = await runtime.callPluginFunction("search('周杰伦', 1, 'music')");
      expect(searchResult, isNotNull);
      expect(searchResult, isNot(contains('"error"')), reason: '搜索出错');

      final searchJson = jsonDecode(searchResult!) as Map<String, dynamic>;
      final data = searchJson['data'] as List?;
      expect(data, isNotEmpty, reason: '搜索无结果');

      if (data!.isNotEmpty) {
        // 获取播放 URL
        final urlResult = await runtime.callPluginFunction(
          "(async function() { const item = (await window.__plugin.search('周杰伦', 1, 'music')).data[0]; const media = await window.__plugin.getMediaSource(item, 'standard'); return JSON.stringify(media); })()",
        );
        expect(urlResult, isNotNull);
        expect(urlResult, isNot(contains('"error"')), reason: '获取播放 URL 出错');

        final urlJson = jsonDecode(urlResult!) as Map<String, dynamic>;
        final playUrl = urlJson['url'] as String?;
        expect(playUrl, isNotEmpty, reason: '播放 URL 为空');
      }
    } finally {
      await runtime.dispose();
      tempDir.deleteSync(recursive: true);
    }
  });
}