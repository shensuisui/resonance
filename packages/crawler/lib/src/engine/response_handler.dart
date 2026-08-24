import 'package:expr/expr.dart';
import 'rule_config.dart';

/// 响应处理器：解析响应数据，提取列表和字段
class ResponseHandler {
  /// 用 listRule 定位列表容器
  /// data 可以是 Map/List（JSON）或 String（HTML/XML/Text）
  static List<dynamic> extractList(dynamic data, String listRule) {
    initExprEngine();
    final result = evaluate(listRule, data);
    if (result == null) return [];
    if (result is List) return result;
    return [result];
  }

  /// 用 itemRules 提取单个 item 的所有字段
  static Map<String, dynamic> extractItem(dynamic item, Map<String, String> itemRules) {
    initExprEngine();
    final fields = <String, dynamic>{};
    for (final entry in itemRules.entries) {
      final value = evaluate(entry.value, item);
      if (value != null) {
        fields[entry.key] = value;
      }
    }
    return fields;
  }

  /// 提取分页信息
  static Map<String, dynamic>? extractPagination(dynamic data, PaginationRule? rule) {
    if (rule == null) return null;
    initExprEngine();

    final info = <String, dynamic>{'type': rule.type};

    switch (rule.type) {
      case 'page':
        if (rule.pageParam != null) {
          info['nextPage'] = data is Map ? data[rule.pageParam] : null;
        }
        break;
      case 'offset':
        if (rule.offsetParam != null && data is Map) {
          info['nextOffset'] = data[rule.offsetParam];
        }
        break;
      case 'cursor':
        if (rule.cursorRule != null) {
          info['nextCursor'] = evaluate(rule.cursorRule!, data);
        }
        break;
    }

    // 提取总数
    if (rule.totalRule != null) {
      final total = evaluate(rule.totalRule!, data);
      if (total != null) info['total'] = total;
    }

    return info;
  }
}