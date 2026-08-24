import 'package:core/core.dart';
import 'package:expr/expr.dart';
import '../http/http_client.dart';
import 'rule_config.dart';
import 'response_handler.dart';

/// 规则执行引擎：执行搜索、详情、歌词、歌单等流程
class RuleExecutor {
  final RuleConfig _rule;
  final HttpClient _httpClient;

  RuleExecutor(this._rule, {HttpClient? httpClient})
      : _httpClient = httpClient ??
            HttpClient(baseUrl: _rule.source.baseUrl);

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
    final response = await _httpClient.get(url, headers: searchRule.headers, responseType: searchRule.responseType);

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
    final pagination = ResponseHandler.extractPagination(response.data, searchRule.pagination);

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
  Future<Map<String, dynamic>> executeSongDetail(String id) async {
    final detailRule = _rule.songDetail;
    if (detailRule == null) return {};

    final url = HttpClient.resolveUrl(detailRule.url, {
      'id': id,
      'baseUrl': _rule.source.baseUrl ?? '',
    });

    final response = await _httpClient.get(url, headers: detailRule.headers, responseType: detailRule.responseType);
    final items = ResponseHandler.extractList(response.data, detailRule.listRule);

    if (items.isEmpty) return {};
    return ResponseHandler.extractItem(items.first, detailRule.itemRules);
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

    return null;
  }

  /// 获取歌单
  Future<SearchResult> executePlaylist(String id) async {
    final playlistRule = _rule.playlist;
    if (playlistRule == null) {
      return SearchResult(songs: [], sourceId: _rule.source.id);
    }

    final url = HttpClient.resolveUrl(playlistRule.url, {
      'id': id,
      'baseUrl': _rule.source.baseUrl ?? '',
    });

    final response = await _httpClient.get(url, headers: playlistRule.headers, responseType: playlistRule.responseType);
    final items = ResponseHandler.extractList(response.data, playlistRule.listRule);

    final songs = <Song>[];
    for (final item in items) {
      final fields = ResponseHandler.extractItem(item, playlistRule.itemRules);
      final song = _fieldsToSong(fields);
      if (song != null) songs.add(song);
    }

    return SearchResult(
      songs: songs,
      sourceId: _rule.source.id,
      hasMore: false,
    );
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