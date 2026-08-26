import 'dart:convert';
import 'package:core/core.dart';
import '../runtime/js_runtime.dart'
    if (dart.library.html) '../runtime/js_runtime_web.dart';

/// 基于 JS 运行时的插件源
/// 通过 JsRuntime 执行 MusicFree 插件 JS 代码
class JsPluginSource extends MusicSource {
  final JsRuntime _runtime;
  final String _name;
  final String _id;

  /// 缓存搜索结果中的原始 musicItem（id → JSON 字符串）
  /// 避免获取播放 URL 时重新搜索导致 songmid 不一致
  final Map<String, String> _itemCache = {};

  JsPluginSource(this._runtime, this._name, {String? id})
      : _id = id ?? _name.toLowerCase().replaceAll(' ', '_');

  @override
  SourceInfo get sourceInfo => SourceInfo(
        id: _id,
        name: _name,
        type: SourceType.plugin,
        enabled: true,
      );

  @override
  Future<SearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 20,
  }) async {
    final result = await _runtime.callPluginFunction(
      "search('${_escapeJs(keyword)}', $page, 'music')",
    );
    // 缓存原始 musicItem，供 getSongUrl / getLyrics 使用
    if (result != null) {
      try {
        final json = jsonDecode(result) as Map<String, dynamic>;
        final data = json['data'] as List?;
        if (data != null) {
          for (final item in data) {
            if (item is Map<String, dynamic>) {
              final id = item['id']?.toString();
              if (id != null) {
                _itemCache[id] = jsonEncode(item);
              }
            }
          }
        }
      } catch (_) {}
    }
    return _parseSearchResult(result);
  }

  @override
  Future<Song> getSongDetail(String id) async {
    // 先搜索获取歌曲信息
    final result = await _runtime.callPluginFunction(
      "search('${_escapeJs(id)}', 1, 'music')",
    );
    final parsed = _parseSearchResult(result);
    if (parsed.songs.isNotEmpty) {
      return parsed.songs.first;
    }
    throw Exception('Song not found: $id');
  }

  @override
  Future<String> getSongUrl(String id) async {
    // 优先使用缓存的原始 musicItem（避免重新搜索导致 songmid 不一致）
    final cachedItem = _itemCache[id];
    final itemJson = cachedItem != null
        ? cachedItem
        : jsonEncode({'id': id});

    final result = await _runtime.callPluginFunction(
      '''
      (async function() {
        var item = $itemJson;
        if (typeof window.__plugin.getMediaSource === "function") {
          var media = await window.__plugin.getMediaSource(item, "standard");
          return JSON.stringify({url: media ? (media.url || "") : ""});
        }
        return JSON.stringify({url: ""});
      })()
      ''',
    );
    if (result != null) {
      try {
        final json = jsonDecode(result) as Map<String, dynamic>;
        return json['url'] as String? ?? '';
      } catch (_) {}
    }
    return '';
  }

  @override
  Future<Lyrics?> getLyrics(String id) async {
    // 优先使用缓存的原始 musicItem
    final cachedItem = _itemCache[id];
    final itemJson = cachedItem != null
        ? cachedItem
        : jsonEncode({'id': id});

    final result = await _runtime.callPluginFunction(
      '''
      (async function() {
        var item = $itemJson;
        if (typeof window.__plugin.getLyric === "function") {
          var lyric = await window.__plugin.getLyric(item);
          return JSON.stringify({lrc: lyric.rawLrc || "", trans: lyric.translation || ""});
        }
        return JSON.stringify({lrc: "", trans: ""});
      })()
      ''',
    );
    if (result != null) {
      try {
        final json = jsonDecode(result) as Map<String, dynamic>;
        final lrc = json['lrc'] as String?;
        if (lrc != null && lrc.isNotEmpty) {
          return Lyrics(songId: id, sourceId: _id, isLrc: lrc.contains('['));
        }
      } catch (_) {}
    }
    return null;
  }

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

  SearchResult _parseSearchResult(String? result) {
    if (result == null) {
      return SearchResult(songs: [], sourceId: _id);
    }

    try {
      final json = jsonDecode(result) as Map<String, dynamic>;
      if (json.containsKey('error')) {
        return SearchResult(songs: [], sourceId: _id);
      }

      final data = json['data'] as List?;
      if (data == null) {
        return SearchResult(songs: [], sourceId: _id);
      }

      final songs = <Song>[];
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          final song = _parseSongItem(item);
          if (song != null) songs.add(song);
        }
      }

      return SearchResult(
        songs: songs,
        sourceId: _id,
        hasMore: json['isEnd'] == false,
      );
    } catch (_) {
      return SearchResult(songs: [], sourceId: _id);
    }
  }

  Song? _parseSongItem(Map<String, dynamic> item) {
    final id = item['id']?.toString();
    final title = item['title']?.toString();
    if (id == null || title == null) return null;

    return Song(
      id: id,
      sourceId: _id,
      title: title,
      artist: item['artist']?.toString() ?? '',
      album: item['album']?.toString(),
      coverUrl: item['artwork']?.toString(),
      duration: item['duration'] is int ? item['duration'] as int : null,
      playUrl: item['url']?.toString(),
      lyricUrl: item['lrc']?.toString(),
    );
  }

  String _escapeJs(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');
  }
}

/// 创建 JS 插件源的工厂方法
class JsPluginFactory {
  /// 从 JS 代码创建插件源
  static Future<JsPluginSource?> create(String jsContent) async {
    try {
      // 提取插件名称
      final nameMatch = RegExp(r"""(?:name|platform)\s*[:=]\s*["']([^"']+)["']""").firstMatch(jsContent);
      final name = nameMatch?.group(1) ?? 'JS插件';

      // 初始化运行时并加载插件
      final runtime = JsRuntime();
      await runtime.init();
      await runtime.loadPlugin(jsContent);

      // 检查插件是否加载成功
      final loaded = await runtime.isPluginLoaded();
      if (!loaded) {
        await runtime.dispose();
        return null;
      }

      return JsPluginSource(runtime, name);
    } catch (e) {
      return null;
    }
  }
}