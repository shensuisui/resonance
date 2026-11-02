import 'package:core/core.dart';
import 'package:expr/expr.dart';
import '../http/http_client.dart';
import 'rule_config.dart';
import 'value_parse.dart';
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

  /// preflight 缓存状态：是否已执行 + 执行时间
  bool _preflightExecuted = false;
  DateTime? _preflightTime;

  RuleExecutor(this._rule, {HttpClient? httpClient})
      : _httpClient = httpClient ??
            HttpClient(baseUrl: _rule.source.baseUrl);

  /// 确保前置流程已执行（带缓存）
  ///
  /// 如果规则配置了 [PreflightRule]，在首次请求和缓存过期时执行前置步骤。
  /// 步骤间通过 extract 提取变量，注入后续步骤的 URL/body 模板。
  /// Cookie 由 HttpClient 的 interceptor 自动跨步骤持久化。
  Future<void> _ensurePreflight() async {
    final preflight = _rule.preflight;
    if (preflight == null || preflight.steps.isEmpty) return;

    // 检查缓存是否有效
    if (_preflightExecuted && _preflightTime != null) {
      if (preflight.cacheMinutes == null) {
        // null = 永久缓存，只执行一次
        return;
      }
      final expiry = _preflightTime!
          .add(Duration(minutes: preflight.cacheMinutes!));
      if (DateTime.now().isBefore(expiry)) {
        return; // 缓存未过期
      }
      // 缓存过期，清除 cookie 重新认证
      _httpClient.clearCookies();
    }

    // 执行前置步骤
    final vars = <String, String>{
      'baseUrl': _rule.source.baseUrl ?? '',
    };
    await _runSteps(preflight.steps, vars);

    _preflightExecuted = true;
    _preflightTime = DateTime.now();
  }

  /// 顺序执行一组流程步骤（前置流程与多步歌曲详情共用）
  ///
  /// 步骤间通过 [PreflightStep.extract] 提取变量注入后续步骤的 url/body/headers；
  /// [fields] 非空时，带 listRule/itemRules 的步骤会把提取到的字段写进去
  /// （多步详情用它承载"末步才拿得到的字段"，如播放地址）。
  Future<void> _runSteps(
    List<PreflightStep> steps,
    Map<String, String> vars, {
    Map<String, dynamic>? fields,
  }) async {
    for (final step in steps) {
      final url = HttpClient.resolveUrl(step.url, vars);
      final resolvedBody =
          step.body == null ? null : HttpClient.resolveUrl(step.body!, vars);
      // 请求头也支持变量注入（如 Referer 里带歌曲 id）
      final headers = step.headers.map(
        (k, v) => MapEntry(k, HttpClient.resolveUrl(v, vars)),
      );

      final HttpResponse response;
      if (step.method.toUpperCase() == 'POST') {
        response = await _httpClient.post(
          url,
          headers: headers,
          body: resolvedBody,
          contentType: step.contentType,
          responseType: step.responseType,
        );
      } else {
        response = await _httpClient.get(
          url,
          headers: headers,
          responseType: step.responseType,
        );
      }

      // 从响应提取变量（用 expr DSL）
      if (step.extract != null && step.extract!.isNotEmpty) {
        initExprEngine();
        for (final entry in step.extract!.entries) {
          final result = evaluate(entry.value, response.data);
          // 结果是列表时取首元素（CSS 提取后缀返回列表）
          final value = result is List
              ? result.first?.toString() ?? ''
              : result?.toString() ?? '';
          vars[entry.key] = value;
        }
      }

      // 末步字段（多步详情用）
      final itemRules = step.itemRules;
      if (fields != null && step.listRule != null && itemRules != null) {
        final items = ResponseHandler.extractList(response.data, step.listRule!);
        if (items.isNotEmpty) {
          fields.addAll(ResponseHandler.extractItem(items.first, itemRules));
        }
      }
    }
  }

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

    // 0. 确保前置流程已执行（人机验证/登录等）
    await _ensurePreflight();

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

    // 0. 确保前置流程已执行
    await _ensurePreflight();

    // 多步模式：按 steps 顺序执行（如先抓详情页拿加密 id、再 POST 换播放地址），
    // 变量池与末步字段一起作为详情字段返回。
    final steps = detailRule.steps;
    if (steps != null && steps.isNotEmpty) {
      final vars = <String, String>{
        'id': id,
        'baseUrl': _rule.source.baseUrl ?? '',
      };
      final fields = <String, dynamic>{};
      await _runSteps(steps, vars, fields: fields);
      return {...vars, ...fields};
    }

    final url = HttpClient.resolveUrl(detailRule.url, {
      'id': id,
      'baseUrl': _rule.source.baseUrl ?? '',
    });
    // 记录实际请求的接口 URL（排查播放 URL 为空/失败时定位问题）
    SourceLogBus.instance.emit(
      _rule.source.id, SourceLogLevel.info, '歌曲详情',
      'id=$id 请求 URL=$url');

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
        SourceLogBus.instance.emit(
          _rule.source.id, SourceLogLevel.warn, '歌曲详情',
          'id=$id URL=$url 302 无 Location，未取到播放地址');
        return {};
      }

      // 常规 JSON/HTML 类型：按 method 分发 GET/POST
      // POST 时 body 模板同样支持 {id}/{baseUrl} 占位（如 id={id}&type=music）
      final HttpResponse response;
      if (detailRule.method.toUpperCase() == 'POST') {
        final body = detailRule.body != null
            ? HttpClient.resolveUrl(detailRule.body!, {
                'id': id,
                'baseUrl': _rule.source.baseUrl ?? '',
              })
            : null;
        response = await _httpClient.post(
          url,
          headers: detailRule.headers,
          body: body,
          contentType: detailRule.contentType,
          responseType: detailRule.responseType,
        );
      } else {
        response = await _httpClient.get(
          url,
          headers: detailRule.headers,
          responseType: detailRule.responseType,
        );
      }
      final items = ResponseHandler.extractList(response.data, detailRule.listRule);
      if (items.isEmpty) {
        SourceLogBus.instance.emit(
          _rule.source.id, SourceLogLevel.warn, '歌曲详情',
          'id=$id URL=$url 响应无列表项，未取到播放地址');
        return {};
      }
      return ResponseHandler.extractItem(items.first, detailRule.itemRules);
    } catch (e) {
      SourceLogBus.instance.emit(
        _rule.source.id, SourceLogLevel.error, '歌曲详情',
        'id=$id URL=$url 请求失败: $e');
      return {};
    }
  }

  /// 获取歌词
  Future<String?> executeLyric(String id, {String? lyricUrl}) async {
    final lyricRule = _rule.lyric;
    if (lyricRule == null) return null;

    // 0. 确保前置流程已执行
    await _ensurePreflight();

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
        // CSS 提取返回列表，直接 toString 会得到 "[歌词]"；这里取首元素
        final value = result is List ? result.firstOrNull : result;
        return value?.toString();
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

    // 0. 确保前置流程已执行
    await _ensurePreflight();

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

    // 0. 确保前置流程已执行
    await _ensurePreflight();

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
    // 统一走 parseFieldText：@CSS/@XPath 命中多个节点时字段是 List，
    // 直接 toString() 会把 List 的「[x]」表示法当成标题（真机标题全是 [稻香]）
    final id = parseFieldText(fields['id']);
    final title = parseFieldText(fields['title']);
    if (id == null || title == null) return null;

    return Song(
      id: id,
      sourceId: _rule.source.id,
      title: title,
      artist: parseFieldText(fields['artist']) ?? '',
      album: parseFieldText(fields['album']),
      coverUrl:
          parseFieldText(fields['cover']) ?? parseFieldText(fields['coverUrl']),
      duration: parseDurationSeconds(parseFieldText(fields['duration'])),
      playUrl: parseFieldText(fields['playUrl']) ?? parseFieldText(fields['url']),
      lyricUrl: parseFieldText(fields['lyricUrl']),
      extra: Map.from(fields)
        ..removeWhere((k, v) => [
              'id', 'title', 'artist', 'album', 'cover', 'coverUrl',
              'duration', 'playUrl', 'url', 'lyricUrl', 'quality',
            ].contains(k)),
    );
  }

}