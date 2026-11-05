import 'dart:convert';

/// 规则模板里的动态来源占位符。
const String kOriginPlaceholder = '{{ORIGIN}}';

/// 把 data/rule.json 模板里的来源占位符替换成本次请求的 origin。
///
/// 规则文件是可直接编辑的 JSON；App 每次启动从 /rule.json 获取。
/// 调试时只要在任意 url 后追加 `&d=10`，该接口就会延迟 10 秒。
Map<String, dynamic> renderRuleTemplate(String template, {required String origin}) {
  if (!template.contains(kOriginPlaceholder)) {
    throw const FormatException('rule.json 缺少 {{ORIGIN}} 占位符');
  }
  final decoded = jsonDecode(template.replaceAll(kOriginPlaceholder, origin));
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('rule.json 根节点必须是对象');
  }
  return decoded;
}
