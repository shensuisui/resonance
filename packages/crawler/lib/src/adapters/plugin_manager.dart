/// 插件管理器 + 适配器
///
/// 文件操作通过 [file_service] 条件导入实现，
/// Web 平台上文件加载方法返回空。

import 'dart:convert';
import 'package:core/core.dart';
import 'package:path/path.dart' as p;
import '../http/http_client.dart';
import '../file_service.dart';
import '../rule_based_source.dart';
import '../engine/rule_config.dart';
import 'js_plugin_source.dart';

/// 插件信息
class PluginInfo {
  final String name;
  final String url;
  final String type; // 'lx' | 'mf'

  const PluginInfo({required this.name, required this.url, required this.type});
}

/// 插件下载器
class PluginDownloader {
  final HttpClient _httpClient;

  PluginDownloader({HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient(timeout: const Duration(seconds: 30));

  /// 从 URL 下载插件文件到本地路径
  Future<String?> downloadPlugin(String url, String savePath) async {
    try {
      final response = await _httpClient.get(url, responseType: 'text');
      // 创建父目录
      final parentDir = p.dirname(savePath);
      await createDirectory(parentDir);
      // 写入文件
      await writeFileAsString(savePath, response.rawData);
      return savePath;
    } catch (e) {
      SourceLogBus.instance.emit(
        'plugin', SourceLogLevel.error, '插件下载',
        '下载失败 $url → $savePath: $e');
      return null;
    }
  }

  /// 获取默认 MusicFree 插件列表
  static List<PluginInfo> get defaultMusicFreePlugins => [
        const PluginInfo(
          name: 'MusicFree 默认源',
          url: 'https://fastly.jsdelivr.net/gh/Huibq/keep-alive/Music_Free/myPlugins.json',
          type: 'mf',
        ),
      ];

  /// 获取默认落雪插件
  static List<PluginInfo> get defaultLxPlugins => [
        const PluginInfo(
          name: '落雪默认源',
          url: 'https://fastly.jsdelivr.net/gh/Huibq/keep-alive/render_api.js',
          type: 'lx',
        ),
      ];

  void dispose() => _httpClient.dispose();
}

/// 插件管理器
class PluginManager {
  /// 从目录加载所有本地插件
  static Future<List<MusicSource>> loadPluginsFromDirectory(String dirPath) async {
    final sources = <MusicSource>[];
    try {
      final dirExists = await isDirectory(dirPath);
      if (!dirExists) return sources;

      final files = await listFiles(dirPath);
      for (final file in files) {
        final source = await loadPlugin(file);
        if (source != null) sources.add(source);
      }
    } catch (_) {}
    return sources;
  }

  /// 加载单个插件文件
  static Future<MusicSource?> loadPlugin(String filePath) async {
    try {
      final content = await readFileAsString(filePath);
      final ext = p.extension(filePath).toLowerCase();

      switch (ext) {
        case '.json':
          final source = MusicFreeAdapter.convertToSource(content);
          if (source == null) {
            SourceLogBus.instance.emit(
              'plugin', SourceLogLevel.error, '插件加载',
              'MusicFree 插件解析失败: $filePath\n内容前 200 字符: ${content.length > 200 ? content.substring(0, 200) : content}');
          }
          return source;
        case '.js':
          final source = await LxMusicAdapter.tryCreate(content);
          if (source == null) {
            SourceLogBus.instance.emit(
              'plugin', SourceLogLevel.error, '插件加载',
              '落雪插件创建失败（JS 运行时不可用或插件无效）: $filePath');
          }
          return source;
        default:
          SourceLogBus.instance.emit(
            'plugin', SourceLogLevel.warn, '插件加载',
            '不支持的插件扩展名: $filePath（$ext）');
          return null;
      }
    } catch (e, st) {
      SourceLogBus.instance.emit(
        'plugin', SourceLogLevel.error, '插件加载',
        '读取插件文件失败 $filePath: $e\n$st');
      return null;
    }
  }
}

/// MusicFree 插件适配器
class MusicFreeAdapter {
  /// 将 MusicFree 插件 JSON 转换为 MusicSource
  static MusicSource? convertToSource(String jsonContent) {
    try {
      final json = jsonDecode(jsonContent);
      if (json is List) {
        if (json.isEmpty) return null;
        return _convertSingle(json.first as Map<String, dynamic>);
      }
      if (json is Map) {
        return _convertSingle(json.cast<String, dynamic>());
      }
      SourceLogBus.instance.emit(
        'plugin', SourceLogLevel.error, '插件解析',
        'MusicFree 插件 JSON 顶层既非 List 也非 Map');
      return null;
    } catch (e) {
      SourceLogBus.instance.emit(
        'plugin', SourceLogLevel.error, '插件解析',
        'MusicFree 插件 JSON 解析失败: $e\n内容前 200 字符: '
        '${jsonContent.length > 200 ? jsonContent.substring(0, 200) : jsonContent}');
      return null;
    }
  }

  static MusicSource? _convertSingle(Map<String, dynamic> plugin) {
    try {
      final name = plugin['name'] as String? ?? 'Unknown';
      final id = plugin['id'] as String? ?? name.toLowerCase().replaceAll(' ', '_');
      final baseUrl = plugin['url'] as String?;

      final config = RuleConfig(
        source: SourceRule(id: id, name: name, baseUrl: baseUrl),
        search: _buildSearchRule(plugin),
        songDetail: _buildDetailRule(plugin),
      );

      return RuleBasedMusicSource(config);
    } catch (e) {
      SourceLogBus.instance.emit(
        'plugin', SourceLogLevel.error, '插件解析',
        'MusicFree 插件结构转换失败: $e\n插件字段: $plugin');
      return null;
    }
  }

  static FlowRule? _buildSearchRule(Map<String, dynamic> plugin) {
    final search = plugin['search'] as Map<String, dynamic>?;
    if (search == null) return null;

    return FlowRule(
      url: search['url'] as String? ?? '/search?keyword={keyword}',
      method: (search['method'] as String?) ?? 'GET',
      responseType: (search['type'] as String?) ?? 'json',
      listRule: search['listRule'] as String? ?? r'$.data',
      itemRules: _buildItemRules(search),
    );
  }

  static FlowRule? _buildDetailRule(Map<String, dynamic> plugin) {
    final detail = plugin['detail'] as Map<String, dynamic>?;
    if (detail == null) return null;

    return FlowRule(
      url: detail['url'] as String? ?? '/song?id={id}',
      method: (detail['method'] as String?) ?? 'GET',
      responseType: (detail['type'] as String?) ?? 'json',
      listRule: detail['listRule'] as String? ?? r'$.data',
      itemRules: _buildItemRules(detail),
    );
  }

  static Map<String, String> _buildItemRules(Map<String, dynamic> section) {
    return {
      'id': (section['idRule'] as String?) ?? 'id',
      'title': (section['titleRule'] as String?) ?? 'title',
      'artist': (section['artistRule'] as String?) ?? 'artist',
      'cover': (section['coverRule'] as String?) ?? 'cover',
      'duration': (section['durationRule'] as String?) ?? 'duration',
      'playUrl': (section['playUrlRule'] as String?) ?? 'playUrl',
    };
  }
}

/// 落雪音乐插件适配器
class LxMusicAdapter {
  /// 尝试创建落雪插件源
  /// 使用 JsRuntime 执行插件 JS 代码
  /// JS 运行时不可用时返回 null
  static Future<MusicSource?> tryCreate(String content) async {
    if (content.trim().isEmpty) return null;
    return JsPluginFactory.create(content);
  }
}
