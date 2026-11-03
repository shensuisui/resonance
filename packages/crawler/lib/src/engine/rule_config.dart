/// 规则配置数据模型
/// 对应规则文件 JSON 的结构

class SourceRule {
  final String id;
  final String name;
  final String? baseUrl;
  final String? icon;

  /// 是否在「音乐库」页作为分栏展示（默认展示）
  final bool showInLibrary;

  /// 是否在「音乐源」页可见（默认可见）
  final bool visible;

  const SourceRule({
    required this.id,
    required this.name,
    this.baseUrl,
    this.icon,
    this.showInLibrary = true,
    this.visible = true,
  });

  factory SourceRule.fromJson(Map<String, dynamic> json) => SourceRule(
        id: json['id'] as String,
        name: json['name'] as String,
        baseUrl: json['baseUrl'] as String?,
        icon: json['icon'] as String?,
        showInLibrary: json['showInLibrary'] as bool? ?? true,
        visible: json['visible'] as bool? ?? true,
      );
}

class PaginationRule {
  final String type; // page / offset / cursor
  final String? pageParam;
  final String? offsetParam;
  final String? limitParam;
  final int? limitValue;
  final String? cursorParam;
  final String? cursorRule;
  final String? totalRule;
  final String? totalRegex;

  const PaginationRule({
    required this.type,
    this.pageParam,
    this.offsetParam,
    this.limitParam,
    this.limitValue,
    this.cursorParam,
    this.cursorRule,
    this.totalRule,
    this.totalRegex,
  });

  factory PaginationRule.fromJson(Map<String, dynamic> json) => PaginationRule(
        type: json['type'] as String,
        pageParam: json['pageParam'] as String?,
        offsetParam: json['offsetParam'] as String?,
        limitParam: json['limitParam'] as String?,
        limitValue: json['limitValue'] as int?,
        cursorParam: json['cursorParam'] as String?,
        cursorRule: json['cursorRule'] as String?,
        totalRule: json['totalRule'] as String?,
        totalRegex: json['totalRegex'] as String?,
      );
}

/// 人机验证规则：源站要求验证时去哪里取验证图、如何回传验证码
///
/// 背景：部分源对多数曲目要求先过验证才给播放地址（如歌曲宝返回
/// {"code":2,"msg":"请完成人机验证后继续"}）。把这件事做成**配置**：
/// 引擎负责"发现挑战 → 取验证图 → 带验证码重试"，端点与字段名由规则声明，
/// 引擎里不写任何源名。
class CaptchaRule {
  /// 取验证图的接口（相对 baseUrl）
  final String endpoint;

  /// 取图请求方法
  final String method;

  /// 取图请求头
  final Map<String, String> headers;

  /// 取图响应类型
  final String responseType;

  /// 从取图响应里取图（data:image/... 或纯 base64）
  final String imagePath;

  /// 从取图响应里取校验 key
  final String keyPath;

  /// 重试时验证码的回传字段名
  final String codeField;

  /// 重试时 key 的回传字段名
  final String keyField;

  /// 哪个响应 code 表示"需要人机验证"
  final int challengeCode;

  /// 从挑战响应里取提示语的表达式（可空）
  final String? messagePath;

  const CaptchaRule({
    required this.endpoint,
    this.method = 'GET',
    this.headers = const {},
    this.responseType = 'json',
    required this.imagePath,
    required this.keyPath,
    this.codeField = 'captchaCode',
    this.keyField = 'key',
    this.challengeCode = 2,
    this.messagePath,
  });

  /// 解析配置（必填项缺失时返回 null，表示该源没有验证流程）
  static CaptchaRule? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final endpoint = json['endpoint'] as String?;
    final imagePath = json['imagePath'] as String?;
    final keyPath = json['keyPath'] as String?;
    if (endpoint == null || imagePath == null || keyPath == null) return null;
    return CaptchaRule(
      endpoint: endpoint,
      method: (json['method'] as String?) ?? 'GET',
      headers: (json['headers'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          const {},
      responseType: (json['responseType'] as String?) ?? 'json',
      imagePath: imagePath,
      keyPath: keyPath,
      codeField: (json['codeField'] as String?) ?? 'captchaCode',
      keyField: (json['keyField'] as String?) ?? 'key',
      challengeCode: (json['challengeCode'] as num?)?.toInt() ?? 2,
      messagePath: json['messagePath'] as String?,
    );
  }
}

class FlowRule {
  final String url;
  final String method;
  final Map<String, String> headers;
  final String responseType;
  final String listRule;
  final Map<String, String> itemRules;
  /// POST 请求体模板，可用 {变量名} 占位（method 为 POST 时生效）
  final String? body;
  /// POST Content-Type（method 为 POST 时生效，默认 application/x-www-form-urlencoded）
  final String? contentType;
  final PaginationRule? pagination;
  /// URL 参数表达式：键为模板变量名，值为 expr DSL 表达式
  /// 表达式对输入参数求值，结果替换 URL 中的 {变量名}
  /// 用于从复合 ID 拆分出 server/id 等场景
  final Map<String, String>? params;
  /// 歌单元数据提取规则：键为 Playlist 字段名，值为 expr DSL 表达式
  /// 从响应根对象提取歌单名称、封面等（区别于 itemRules 从列表项提取）
  final Map<String, String>? playlistInfo;

  /// 多步流程（可选）
  ///
  /// 配置后按步骤顺序执行（如"先抓详情页拿加密 id、再 POST 换播放地址"）：
  /// 每步 extract 的变量累积成变量池并注入后续步骤的 url/body/headers，
  /// 末步可用 listRule/itemRules 补充字段；变量池与末步字段一并返回。
  final List<PreflightStep>? steps;

  /// 人机验证配置（源站要求验证时用；没有该流程的源留空）
  final CaptchaRule? captcha;

  const FlowRule({
    required this.url,
    this.method = 'GET',
    this.headers = const {},
    this.responseType = 'json',
    required this.listRule,
    required this.itemRules,
    this.body,
    this.contentType,
    this.pagination,
    this.params,
    this.playlistInfo,
    this.steps,
    this.captcha,
  });

  factory FlowRule.fromJson(Map<String, dynamic> json) => FlowRule(
        // 多步流程（steps）不需要顶层 url：URL 由各步骤自带
        url: (json['url'] as String?) ?? '',
        method: (json['method'] as String?) ?? 'GET',
        headers: (json['headers'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as String)) ??
            {},
        responseType: (json['responseType'] as String?) ?? 'json',
        // 单请求流程必须给 listRule/itemRules；多步流程（steps）由各步骤自带，
        // 因此这里放宽为可选，避免 songDetail 的 steps 写法解析即崩。
        listRule: (json['listRule'] as String?) ?? r'$',
        itemRules: (json['itemRules'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as String)) ??
            const {},

        body: json['body'] as String?,
        contentType: json['contentType'] as String?,
        pagination: json['pagination'] != null
            ? PaginationRule.fromJson(json['pagination'] as Map<String, dynamic>)
            : null,
        params: (json['params'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v as String)),
        playlistInfo: (json['playlistInfo'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v as String)),
        steps: (json['steps'] as List<dynamic>?)
            ?.map((e) => PreflightStep.fromJson(e as Map<String, dynamic>))
            .toList(),
        captcha: CaptchaRule.fromJson(json['captcha'] as Map<String, dynamic>?),
      );
}

class LyricRuleConfig {
  final String url;
  final String method;
  final Map<String, String> headers;
  final String responseType;
  final String? listRule;
  final String? contentRule;

  /// URL 参数表达式：键为模板变量名，值为 expr DSL 表达式
  ///
  /// 与 [FlowRule.params] 同义，用于「曲目 ID 与歌词接口需要的 ID 不是同一个」
  /// 的场景（如复合 ID `trackId~picId` 需要先拆出 trackId）。
  final Map<String, String>? params;

  /// 译文歌词表达式（多为 `$.tlyric`）
  ///
  /// 配置后把译文按**时间戳对齐**合并进 [contentRule] 的结果：
  /// 同一时间戳的一行变成 `原文{join}译文`，译文为空则原样返回原文。
  final String? translationRule;

  /// 原文与译文合并时的连接符（[translationRule] 未配置时无意义，默认 " / "）
  final String? translationJoin;

  const LyricRuleConfig({
    required this.url,
    this.method = 'GET',
    this.headers = const {},
    this.responseType = 'text',
    this.listRule,
    this.contentRule,
    this.params,
    this.translationRule,
    this.translationJoin,
  });

  factory LyricRuleConfig.fromJson(Map<String, dynamic> json) => LyricRuleConfig(
        url: json['url'] as String,
        method: (json['method'] as String?) ?? 'GET',
        headers: (json['headers'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as String)) ??
            {},
        responseType: (json['responseType'] as String?) ?? 'text',
        listRule: json['listRule'] as String?,
        contentRule: json['contentRule'] as String?,
        params: (json['params'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v as String)),
        translationRule: json['translationRule'] as String?,
        translationJoin: json['translationJoin'] as String?,
      );
}

/// 前置流程步骤：在真实请求前执行的一个步骤
///
/// 用于人机验证、CSRF token 提取、登录、签名等场景。
/// 步骤间通过 [extract] 提取变量，注入后续步骤的 URL/body/headers。
class PreflightStep {
  /// HTTP 方法：GET 或 POST
  final String method;

  /// URL 模板，可用 {变量名} 占位（由前面步骤的 extract 结果填充）
  final String url;

  /// 请求头
  final Map<String, String> headers;

  /// 响应类型：html / json / text
  final String responseType;

  /// POST body 模板，可用 {变量名} 占位
  final String? body;

  /// POST Content-Type
  final String? contentType;

  /// 从此步响应提取的变量：键为变量名，值为 expr DSL 表达式
  /// 提取结果注入后续步骤的 URL/body/headers 模板
  final Map<String, String>? extract;

  /// 列表定位规则（多步流程的末步用；普通前置步骤不传）
  final String? listRule;

  /// 字段提取规则（多步流程的末步用；普通前置步骤不传）
  final Map<String, String>? itemRules;

  /// 该步失败（超时/非 2xx）时是否跳过而不是中断整个流程
  ///
  /// 用于"锦上添花"的步骤：如封面解析失败不该把播放地址一起毁掉。
  final bool optional;

  const PreflightStep({
    required this.method,
    required this.url,
    this.headers = const {},
    this.responseType = 'html',
    this.body,
    this.contentType,
    this.extract,
    this.listRule,
    this.itemRules,
    this.optional = false,
  });

  factory PreflightStep.fromJson(Map<String, dynamic> json) => PreflightStep(
        method: (json['method'] as String?) ?? 'GET',
        url: json['url'] as String,
        headers: (json['headers'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as String)) ??
            {},
        responseType: (json['responseType'] as String?) ?? 'html',
        body: json['body'] as String?,
        contentType: json['contentType'] as String?,
        extract: (json['extract'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v as String)),
        listRule: json['listRule'] as String?,
        itemRules: (json['itemRules'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v as String)),
        optional: json['optional'] as bool? ?? false,
      );
}

/// 前置流程配置：描述在真实请求前需要执行的一组步骤
///
/// 典型场景：
/// - 6uq.cn 人机验证：GET 取 CSRF token → POST 换 cookie
/// - 登录态：POST 登录 → 提取 session token → 注入后续请求 header
/// - 签名：GET 取密钥 → 计算签名 → 注入 URL 参数
///
/// 步骤间数据传递：步骤 A 的 [PreflightStep.extract] 提取的变量，
/// 可在步骤 B 的 url/body/headers 模板中用 {变量名} 引用。
/// Cookie 自动跨步骤持久化（由 HttpClient 的 cookie interceptor 处理）。
class PreflightRule {
  /// 前置步骤，按顺序执行
  final List<PreflightStep> steps;

  /// 缓存有效期（分钟），过期后重新执行整套步骤
  /// null 表示只执行一次（整个实例生命周期内有效）
  final int? cacheMinutes;

  const PreflightRule({
    required this.steps,
    this.cacheMinutes,
  });

  factory PreflightRule.fromJson(Map<String, dynamic> json) => PreflightRule(
        steps: (json['steps'] as List<dynamic>)
            .map((e) => PreflightStep.fromJson(e as Map<String, dynamic>))
            .toList(),
        cacheMinutes: json['cacheMinutes'] as int?,
      );
}

class RuleConfig {
  final SourceRule source;
  final FlowRule? search;
  final FlowRule? songDetail;
  final LyricRuleConfig? lyric;
  final FlowRule? playlist;
  /// 推荐歌单列表流程：获取歌单列表（可能来自多个平台）
  final FlowRule? playlistList;
  /// 播放请求头：播放器请求 CDN 地址时需携带的 HTTP 头
  final Map<String, String>? playHeaders;
  /// 前置流程：在真实请求前执行的认证/验证步骤
  final PreflightRule? preflight;

  const RuleConfig({
    required this.source,
    this.search,
    this.songDetail,
    this.lyric,
    this.playlist,
    this.playlistList,
    this.playHeaders,
    this.preflight,
  });

  factory RuleConfig.fromJson(Map<String, dynamic> json) => RuleConfig(
        source: SourceRule.fromJson(json['source'] as Map<String, dynamic>),
        search: json['search'] != null
            ? FlowRule.fromJson(json['search'] as Map<String, dynamic>)
            : null,
        songDetail: json['songDetail'] != null
            ? FlowRule.fromJson(json['songDetail'] as Map<String, dynamic>)
            : null,
        lyric: json['lyric'] != null
            ? LyricRuleConfig.fromJson(json['lyric'] as Map<String, dynamic>)
            : null,
        playlist: json['playlist'] != null
            ? FlowRule.fromJson(json['playlist'] as Map<String, dynamic>)
            : null,
        playlistList: json['playlistList'] != null
            ? FlowRule.fromJson(json['playlistList'] as Map<String, dynamic>)
            : null,
        playHeaders: (json['playHeaders'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v as String)),
        preflight: json['preflight'] != null
            ? PreflightRule.fromJson(json['preflight'] as Map<String, dynamic>)
            : null,
      );
}