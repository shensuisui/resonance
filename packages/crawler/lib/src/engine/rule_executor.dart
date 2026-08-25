import 'package:core/core.dart';
import 'package:expr/expr.dart';
import '../http/http_client.dart';
import 'rule_config.dart';
import 'response_handler.dart';

/// 歌单详情结果：包含歌单元数据和曲目列表
class PlaylistDetailResult {
  final Playlist playlist;
  final List<Song> songs;
  PlaylistDetailResult(this.playlist, this.songs);
}

/// 规则执行引擎：执行搜索、详情、歌词、歌单等流程
class RuleExecutor {
  final RuleConfig _rule;
  final HttpClient _httpClient;

  RuleExecutor(this._rule, {HttpClient? httpClient})
      : _httpClient = httpClient ??
            HttpClient(baseUrl: _rule.source.baseUrl);

  /// 解析 URL 模板，支持 params 表达式参数
  /// params 中的表达式对输入变量求值，结果替换 URL 模板中的 {变量名}
  /// 用于从复合 ID 拆分出 server/id 等场景
  String _resolveUrlWithParams(
    String template,
    Map<String, String> vars,
    Map<String, String>? params,
  ) {
    if (params == null || params.isEmpty) {
      return HttpClient.resolveUrl(template, vars);
    }
    // 初始化表达式引擎
    initExprEngine();
    final resolvedVars = Map<String, String>.from(vars);
    for (final entry in params.entries) {
      final result = evaluate(entry.value, vars);
      resolvedVars[entry.key] = result?.toString() ?? '';
    }
    return HttpClient.resolveUrl(template, resolvedVars);
  }

  /// 执行搜索
  Future<SearchResult> executeSearch(String keyword, {int page = 1}) async {
    final searchRule = _rule.search;
    if (searchRule == null) {
      return SearchResult(songs: [], sourceId: _rule.source.id);
    }

    // 1. 构建 URL
    final url = HttpClient.resolveUrl(searchRule.url, {
      'keyword': Uri.encodeComponent(keyword),
      'page': page.toString(),
      'baseUrl': _rule.source.baseUrl ?? '',
    });

    // 2. 发送请求
    late final HttpResponse response;
    try {
      response = await _httpClient.get(url, headers: searchRule.headers, responseType: searchRule.responseType);
    } catch (_) {
      return SearchResult(songs: [], sourceId: _rule.source.id);
    }

    // 3. 提取列表
    final items = ResponseHandler.extractList(response.data, searchRule.listRule);

    // 4. 提取字段
    final songs = <Song>[];
    for (final item in items) {
      final fields = ResponseHandler.extractItem(item, searchRule.itemRules);
      final song = _fieldsToSong(fields);
      if (song != null) songs.add(song);
    }

    // 5. 提取分页
    final pagination = ResponseHandler.extractPagination(
      response.data,
      searchRule.pagination,
      resultCount: songs.length,
      currentPage: page,
    );

    return SearchResult(
      songs: songs,
      sourceId: _rule.source.id,
      hasMore: pagination != null && pagination['nextCursor'] != null ||
          pagination?['nextPage'] != null ||
          pagination?['nextOffset'] != null,
      nextPage: pagination?['nextPage'] as int?,
      nextOffset: pagination?['nextOffset'] as int?,
      nextCursor: pagination?['nextCursor'] as String?,
    );
  }

  /// 获取歌曲详情
  ///
  /// 支持 responseType: 'redirect' — 用于获取重定向 URL（如枫叶音乐的播放地址）
  /// 当 responseType 为 redirect 时，调用 URL 不跟随重定向，提取 Location header
  Future<Map<String, dynamic>> executeSongDetail(String id) async {
    final detailRule = _rule.songDetail;
    if (detailRule == null) return {};

    final url = HttpClient.resolveUrl(detailRule.url, {
      'id': id,
      'baseUrl': _rule.source.baseUrl ?? '',
    });

    try {
      // 重定向类型：不跟随 302，提取 Location header
      if (detailRule.responseType == 'redirect') {
        final response = await _httpClient.get(
          url,
          headers: detailRule.headers,
          responseType: 'text',
          followRedirects: false,
        );
        if (response.redirectUrl != null) {
          return {'playUrl': response.redirectUrl};
        }
        return {};
      }

      // 常规 JSON/HTML 类型
      final response = await _httpClient.get(url, headers: detailRule.headers, responseType: detailRule.responseType);
      final items = ResponseHandler.extractList(response.data, detailRule.listRule);
      if (items.isEmpty) return {};
      return ResponseHandler.extractItem(items.first, detailRule.itemRules);
    } catch (_) {
      return {};
    }
  }

  /// 获取歌词
  Future<String?> executeLyric(String id, {String? lyricUrl}) async {
    final lyricRule = _rule.lyric;
    if (lyricRule == null) return null;

    final url = HttpClient.resolveUrl(lyricRule.url, {
      'id': id,
      'lyricUrl': lyricUrl ?? '',
      'baseUrl': _rule.source.baseUrl ?? '',
    });

    if (url.isEmpty) return null;

    try {
      final response = await _httpClient.get(url, headers: lyricRule.headers, responseType: lyricRule.responseType);

      if (lyricRule.responseType == 'text') {
        return response.rawData;
      }

      // 非 text 响应，用 contentRule 提取
      if (lyricRule.contentRule != null) {
        initExprEngine();
        final result = evaluate(lyricRule.contentRule!, response.data);
        return result?.toString();
      }
    } catch (_) {}

    return null;
  }

  /// 获取歌单详情（含曲目列表）
  ///
  /// 支持 params 表达式参数：从复合 ID 拆分出 server/id 等
  /// 支持 playlistInfo：从响应根对象提取歌单名称、封面等元数据
  Future<PlaylistDetailResult?> executePlaylist(String id) async {
    final playlistRule = _rule.playlist;
    if (playlistRule == null) return null;

    // 用 params 表达式解析 URL（支持从复合 ID 拆分）
    final url = _resolveUrlWithParams(playlistRule.url, {
      'id': id,
      'baseUrl': _rule.source.baseUrl ?? '',
    }, playlistRule.params);

    try {
      final response = await _httpClient.get(
        url,
        headers: playlistRule.headers,
        responseType: playlistRule.responseType,
      );

      // 提取歌单元数据（从响应根对象）
      String playlistName = id;
      String? coverUrl;
      if (playlistRule.playlistInfo != null) {
        final infoFields = ResponseHandler.extractItem(
          response.data,
          playlistRule.playlistInfo!,
        );
        playlistName = infoFields['title']?.toString() ?? id;
        coverUrl = infoFields['coverUrl']?.toString() ??
            infoFields['cover']?.toString();
      }

      // 提取曲目列表
      final items = ResponseHandler.extractList(response.data, playlistRule.listRule);
      final songs = <Song>[];
      for (final item in items) {
        final fields = ResponseHandler.extractItem(item, playlistRule.itemRules);
        final song = _fieldsToSong(fields);
        if (song != null) songs.add(song);
      }

      final now = DateTime.now();
      final playlist = Playlist(
        id: id,
        name: playlistName,
        songKeys: songs.map((s) => '${s.sourceId}:${s.id}').toList(),
        sourceId: _rule.source.id,
        sourcePlaylistId: id,
        coverUrl: coverUrl,
        createdTime: now,
        modifiedTime: now,
      );

      return PlaylistDetailResult(playlist, songs);
    } catch (_) {
      return null;
    }
  }

  /// 获取推荐歌单列表
  ///
  /// 返回歌单列表（不含曲目），用于歌单发现页
  /// 注意：一个源可能有多个平台的歌单，itemRules 应生成复合 ID 以便后续详情查询
  Future<List<Playlist>> executePlaylistList({int page = 1}) async {
    final listRule = _rule.playlistList;
    if (listRule == null) return [];

    final url = _resolveUrlWithParams(listRule.url, {
      'page': page.toString(),
      'baseUrl': _rule.source.baseUrl ?? '',
    }, listRule.params);

    try {
      final response = await _httpClient.get(
        url,
        headers: listRule.headers,
        responseType: listRule.responseType,
      );

      final items = ResponseHandler.extractList(response.data, listRule.listRule);
      final now = DateTime.now();
      final playlists = <Playlist>[];
      for (final item in items) {
        final fields = ResponseHandler.extractItem(item, listRule.itemRules);
        final pid = fields['id']?.toString();
        final pname = fields['title']?.toString() ?? fields['name']?.toString();
        if (pid == null || pname == null) continue;

        playlists.add(Playlist(
          id: pid,
          name: pname,
          sourceId: _rule.source.id,
          sourcePlaylistId: pid,
          coverUrl: fields['coverUrl']?.toString() ??
              fields['cover']?.toString(),
          createdTime: now,
          modifiedTime: now,
        ));
      }

      return playlists;
    } catch (_) {
      return [];
    }
  }

  /// 将提取的字段映射为 Song 对象
  Song? _fieldsToSong(Map<String, dynamic> fields) {
    final id = fields['id']?.toString();
    final title = fields['title']?.toString();
    if (id == null || title == null) return null;

    return Song(
      id: id,
      sourceId: _rule.source.id,
      title: title,
      artist: fields['artist']?.toString() ?? '',
      album: fields['album']?.toString(),
      coverUrl: fields['cover']?.toString() ?? fields['coverUrl']?.toString(),
      duration: _parseInt(fields['duration']),
      playUrl: fields['playUrl']?.toString() ?? fields['url']?.toString(),
      lyricUrl: fields['lyricUrl']?.toString(),
      extra: Map.from(fields)
        ..removeWhere((k, v) => [
              'id', 'title', 'artist', 'album', 'cover', 'coverUrl',
              'duration', 'playUrl', 'url', 'lyricUrl', 'quality',
            ].contains(k)),
    );
  }

  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }
}