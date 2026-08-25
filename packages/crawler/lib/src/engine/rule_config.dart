/// 规则配置数据模型
/// 对应规则文件 JSON 的结构

class SourceRule {
  final String id;
  final String name;
  final String? baseUrl;
  final String? icon;

  const SourceRule({
    required this.id,
    required this.name,
    this.baseUrl,
    this.icon,
  });

  factory SourceRule.fromJson(Map<String, dynamic> json) => SourceRule(
        id: json['id'] as String,
        name: json['name'] as String,
        baseUrl: json['baseUrl'] as String?,
        icon: json['icon'] as String?,
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

class FlowRule {
  final String url;
  final String method;
  final Map<String, String> headers;
  final String responseType;
  final String listRule;
  final Map<String, String> itemRules;
  final PaginationRule? pagination;
  /// URL 参数表达式：键为模板变量名，值为 expr DSL 表达式
  /// 表达式对输入参数求值，结果替换 URL 中的 {变量名}
  /// 用于从复合 ID 拆分出 server/id 等场景
  final Map<String, String>? params;
  /// 歌单元数据提取规则：键为 Playlist 字段名，值为 expr DSL 表达式
  /// 从响应根对象提取歌单名称、封面等（区别于 itemRules 从列表项提取）
  final Map<String, String>? playlistInfo;

  const FlowRule({
    required this.url,
    this.method = 'GET',
    this.headers = const {},
    this.responseType = 'json',
    required this.listRule,
    required this.itemRules,
    this.pagination,
    this.params,
    this.playlistInfo,
  });

  factory FlowRule.fromJson(Map<String, dynamic> json) => FlowRule(
        url: json['url'] as String,
        method: (json['method'] as String?) ?? 'GET',
        headers: (json['headers'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as String)) ??
            {},
        responseType: (json['responseType'] as String?) ?? 'json',
        listRule: json['listRule'] as String,
        itemRules: (json['itemRules'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v as String)),
        pagination: json['pagination'] != null
            ? PaginationRule.fromJson(json['pagination'] as Map<String, dynamic>)
            : null,
        params: (json['params'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v as String)),
        playlistInfo: (json['playlistInfo'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v as String)),
      );
}

class LyricRuleConfig {
  final String url;
  final String method;
  final Map<String, String> headers;
  final String responseType;
  final String? listRule;
  final String? contentRule;

  const LyricRuleConfig({
    required this.url,
    this.method = 'GET',
    this.headers = const {},
    this.responseType = 'text',
    this.listRule,
    this.contentRule,
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

  const RuleConfig({
    required this.source,
    this.search,
    this.songDetail,
    this.lyric,
    this.playlist,
    this.playlistList,
    this.playHeaders,
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
      );
}