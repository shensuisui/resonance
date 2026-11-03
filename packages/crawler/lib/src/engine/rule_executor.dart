import 'package:core/core.dart';
import 'package:expr/expr.dart';
import '../http/http_client.dart';
import 'lyric_merge.dart';
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
/// 歌曲详情执行结果
///
/// 为什么要连响应一起返回：源站人机验证是"接口成功返回、但内容是挑战"，
/// 只看提取出的字段会分不清"这首没地址"和"源站要求验证"。
class SongDetailOutcome {
  /// 详情字段（含步骤变量池与末步字段）
  final Map<String, dynamic> fields;

  /// 末步原始响应（JSON 为 Map/List，HTML 为 String）
  final dynamic lastResponse;

  /// 源站要求的人机验证（没有则为 null）
  final PlaybackChallenge? challenge;

  const SongDetailOutcome({
    required this.fields,
    this.lastResponse,
    this.challenge,
  });
}

/// 一次验证码解法：规则 + 用户输入的验证码 + 挑战里的 key
class _CaptchaSolution {
  /// 验证规则（字段名等）
  final CaptchaRule rule;

  /// 用户输入的验证码
  final String code;

  /// 挑战带回的 key
  final String? key;

  const _CaptchaSolution(this.rule, this.code, this.key);
}

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
  /// [captcha] 非空时，把它按规则声明的字段名追加到**末步**的 POST body 上
  /// （源站要求人机验证时，浏览器就是在这一步多带 captchaCode + key）。
  ///
  /// 返回**末步响应数据**：判定"是否被源站人机验证拦住"必须看原响应，
  /// 字段提取会把挑战响应里的内容过滤掉，光看字段分不清"没地址"和"被拦"。
  Future<dynamic> _runSteps(
    List<PreflightStep> steps,
    Map<String, String> vars, {
    Map<String, dynamic>? fields,
    _CaptchaSolution? captcha,
  }) async {
    dynamic lastResponse;
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final url = HttpClient.resolveUrl(step.url, vars);
      var resolvedBody =
          step.body == null ? null : HttpClient.resolveUrl(step.body!, vars);
      if (captcha != null && i == steps.length - 1 && resolvedBody != null) {
        resolvedBody = resolvedBody +
            '&' +
            captcha.rule.codeField +
            '=' +
            Uri.encodeComponent(captcha.code) +
            '&' +
            captcha.rule.keyField +
            '=' +
            Uri.encodeComponent(captcha.key ?? '');
      }
      // 请求头也支持变量注入（如 Referer 里带歌曲 id）
      final headers = step.headers.map(
        (k, v) => MapEntry(k, HttpClient.resolveUrl(v, vars)),
      );

      final HttpResponse response;
      try {
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
      } catch (e) {
        // 可选步骤（如封面）失败只记日志、流程继续；必需步骤照旧抛出
        if (!step.optional) rethrow;
        SourceLogBus.instance.emit(_rule.source.id, SourceLogLevel.warn, '步骤跳过',
            '可选步骤 $url 请求失败: $e');
        continue;
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

      lastResponse = response.data;

      // 末步字段（多步详情用）
      final itemRules = step.itemRules;
      if (fields != null && step.listRule != null && itemRules != null) {
        final items = ResponseHandler.extractList(response.data, step.listRule!);
        if (items.isNotEmpty) {
          fields.addAll(ResponseHandler.extractItem(items.first, itemRules));
        }
      }
    }
    return lastResponse;
  }

  /// 末步响应是否是"源站要求人机验证"？是则取回验证图与 key
  ///
  /// 做成配置驱动：端点/表达式/字段名全部来自规则的 captcha 块，
  /// 引擎不认源名，也不替用户破解验证码（只负责把图和 key 交给上层）。
  Future<PlaybackChallenge?> _detectChallenge(
      CaptchaRule? rule, dynamic lastResponse) async {
    if (rule == null || lastResponse is! Map) return null;
    if (lastResponse['code'] != rule.challengeCode) return null;

    final url = HttpClient.resolveUrl(rule.endpoint, {
      'baseUrl': _rule.source.baseUrl ?? '',
    });
    final response = rule.method.toUpperCase() == 'POST'
        ? await _httpClient.post(url,
            headers: rule.headers, responseType: rule.responseType)
        : await _httpClient.get(url,
            headers: rule.headers, responseType: rule.responseType);

    initExprEngine();
    final image = parseFieldText(evaluate(rule.imagePath, response.data)) ?? '';
    final key = parseFieldText(evaluate(rule.keyPath, response.data)) ?? '';
    final message = rule.messagePath == null
        ? ''
        : parseFieldText(evaluate(rule.messagePath!, lastResponse)) ?? '';

    SourceLogBus.instance.emit(_rule.source.id, SourceLogLevel.warn, '人机验证',
        '源站要求验证（' + message + '），验证图' + (image.isEmpty ? '获取失败' : '已获取'));

    return PlaybackChallenge(
      image: image,
      key: key,
      codeField: rule.codeField,
      keyField: rule.keyField,
      message: message,
    );
  }

  /// 把 params 表达式对输入变量求值，产出「占位符 → 值」
  ///
  /// params 用于「一个 ID 要拆成多个接口参数」的场景：搜索侧把节目需要的
  /// 多个 ID 拼成复合 ID，详情/歌词侧用表达式拆回（如 `trackId~picId`
  /// 拆成 {id} 与 {picId}）。结果覆盖同名占位符。
  Map<String, String> _applyParams(
    Map<String, String> vars,
    Map<String, String>? params,
  ) {
    if (params == null || params.isEmpty) return vars;
    initExprEngine();
    final resolved = Map<String, String>.from(vars);
    for (final entry in params.entries) {
      final result = evaluate(entry.value, vars);
      resolved[entry.key] = result?.toString() ?? '';
    }
    return resolved;
  }

  /// 解析 URL 模板，支持 params 表达式参数
  /// params 中的表达式对输入变量求值，结果替换 URL 模板中的 {变量名}
  /// 用于从复合 ID 拆分出 server/id 等场景
  String _resolveUrlWithParams(
    String template,
    Map<String, String> vars,
    Map<String, String>? params,
  ) =>
      HttpClient.resolveUrl(template, _applyParams(vars, params));

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
  /// 支持 responseType: 'redirect' — 接口直接 302 到 CDN 时，用 Location 当播放地址
  /// 当 responseType 为 redirect 时，调用 URL 不跟随重定向，提取 Location header
  /// 歌曲详情（多步流程 + 人机验证）
  ///
  /// [captchaCode]/[captchaKey]：源站要求验证时，带用户输入的验证码重试；
  /// 验证码由用户提供，引擎只负责按规则声明的字段名回传。
  Future<SongDetailOutcome> executeSongDetailOutcome(
    String id, {
    String? captchaCode,
    String? captchaKey,
  }) async {
    final detailRule = _rule.songDetail;
    if (detailRule == null) return const SongDetailOutcome(fields: {});

    final steps = detailRule.steps;
    // 挑战发生在"换播放地址"那一步，只有多步流程才会遇到
    if (steps == null || steps.isEmpty) {
      return SongDetailOutcome(fields: await executeSongDetail(id));
    }

    await _ensurePreflight();

    final vars = _applyParams(<String, String>{
      'id': id,
      'baseUrl': _rule.source.baseUrl ?? '',
    }, detailRule.params);
    final fields = <String, dynamic>{};
    final captchaRule = detailRule.captcha;
    final solution = (captchaCode != null && captchaRule != null)
        ? _CaptchaSolution(captchaRule, captchaCode, captchaKey)
        : null;

    final lastResponse =
        await _runSteps(steps, vars, fields: fields, captcha: solution);
    final challenge = await _detectChallenge(captchaRule, lastResponse);

    return SongDetailOutcome(
      fields: {...vars, ...fields},
      lastResponse: lastResponse,
      challenge: challenge,
    );
  }

  Future<Map<String, dynamic>> executeSongDetail(String id) async {
    final detailRule = _rule.songDetail;
    if (detailRule == null) return {};

    // 0. 确保前置流程已执行
    await _ensurePreflight();

    // 多步模式：按 steps 顺序执行（如先抓详情页拿加密 id、再 POST 换播放地址），
    // 变量池与末步字段一起作为详情字段返回。
    // 复合 ID 先按 params 拆成各接口需要的参数（如 trackId~picId）
    final steps = detailRule.steps;
    if (steps != null && steps.isNotEmpty) {
      final vars = _applyParams(<String, String>{
        'id': id,
        'baseUrl': _rule.source.baseUrl ?? '',
      }, detailRule.params);
      final fields = <String, dynamic>{};
      await _runSteps(steps, vars, fields: fields);
      return {...vars, ...fields};
    }

    final vars = _applyParams(<String, String>{
      'id': id,
      'baseUrl': _rule.source.baseUrl ?? '',
    }, detailRule.params);
    final url = HttpClient.resolveUrl(detailRule.url, vars);
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
            ? HttpClient.resolveUrl(detailRule.body!, vars)
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

    // 复合 ID 先按 params 拆参数（歌词接口要的是 trackId，不是复合 ID）
    final vars = _applyParams(<String, String>{
      'id': id,
      'lyricUrl': lyricUrl ?? '',
      'baseUrl': _rule.source.baseUrl ?? '',
    }, lyricRule.params);
    final url = HttpClient.resolveUrl(lyricRule.url, vars);

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
        final content = value?.toString();
        if (content == null || content.isEmpty) return content;
        return _mergeTranslation(content, lyricRule, response.data);
      }
    } catch (_) {}

    return null;
  }

  /// 按规则把译文合并进原文歌词（[LyricRuleConfig.translationRule] 可选）
  ///
  /// 译文表达式缺失/取不到/为空串时原样返回原文 —— 即"没有译文"与
  /// "规则里没写译文"两条路径行为完全一致。
  String _mergeTranslation(
    String content,
    LyricRuleConfig rule,
    dynamic data,
  ) {
    final translationRule = rule.translationRule;
    if (translationRule == null || translationRule.isEmpty) return content;
    initExprEngine();
    final raw = evaluate(translationRule, data);
    final translation = raw is List ? raw.firstOrNull : raw;
    final result = mergeLyricTranslation(
      content,
      translation?.toString(),
      join: rule.translationJoin ?? ' / ',
    );
    SourceLogBus.instance.emit(
      _rule.source.id,
      SourceLogLevel.info,
      '歌词',
      result.mergedLines > 0
          ? '译文已按时间戳合并 ${result.mergedLines}/${result.originalLines} 行'
          : '译文为空或无法对齐，仅返回原文',
    );
    return result.text;
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