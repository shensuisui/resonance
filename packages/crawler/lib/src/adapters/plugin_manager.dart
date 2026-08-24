import 'dart:convert';
import 'dart:io';
import 'package:core/core.dart';
import '../http/http_client.dart';
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
      final file = File(savePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(response.rawData);
      return savePath;
    } catch (e) {
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
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return sources;

      for (final file in dir.listSync().whereType<File>()) {
        final source = await loadPlugin(file.path);
        if (source != null) sources.add(source);
      }
    } catch (_) {}
    return sources;
  }

  /// 加载单个插件文件
  static Future<MusicSource?> loadPlugin(String filePath) async {
    try {
      final content = File(filePath).readAsStringSync();
      final ext = filePath.split('.').last.toLowerCase();

      switch (ext) {
        case 'json':
          return MusicFreeAdapter.convertToSource(content);
        case 'js':
          return await LxMusicAdapter.tryCreate(content);
        default:
          return null;
      }
    } catch (_) {
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
      return null;
    } catch (_) {
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
    } catch (_) {
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
  /// 如果 JS 运行时不可用，返回 stub 源
  static Future<MusicSource?> tryCreate(String content) async {
    if (content.trim().isEmpty) return null;

    try {
      // 优先尝试 JS 运行时
      final source = await JsPluginFactory.create(content);
      if (source != null) return source;
    } catch (_) {
      // JS 运行时不可用，回退到 stub
    }

    // 回退：返回 stub 源
    final nameMatch = RegExp(r"""(?:name|platform)\s*[:=]\s*["']([^"']+)["']""").firstMatch(content);
    final name = nameMatch?.group(1) ?? '落雪插件';
    return _LxStubSource(name);
  }
}

/// 落雪插件 stub 源（JS 运行时不可用时使用）
class _LxStubSource extends MusicSource {
  final String _name;

  _LxStubSource(this._name);

  @override
  SourceInfo get sourceInfo => SourceInfo(
        id: 'lx_${_name.toLowerCase().replaceAll(' ', '_')}',
        name: '$_name (JS 待支持)',
        type: SourceType.plugin,
        enabled: true,
      );

  @override
  Future<SearchResult> search({required String keyword, int page = 1, int pageSize = 20}) async {
    throw UnsupportedError('JS 运行时不可用，落雪插件暂不可用');
  }

  @override
  Future<Song> getSongDetail(String id) async {
    throw UnsupportedError('JS 运行时不可用，落雪插件暂不可用');
  }

  @override
  Future<String> getSongUrl(String id) async {
    throw UnsupportedError('JS 运行时不可用，落雪插件暂不可用');
  }

  @override
  Future<Lyrics?> getLyrics(String id) async => null;

  @override
  Future<Album?> getAlbum(String id) async => null;

  @override
  Future<Artist?> getArtist(String id) async => null;

  @override
  Future<Playlist?> getPlaylist(String id) async => null;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}
}