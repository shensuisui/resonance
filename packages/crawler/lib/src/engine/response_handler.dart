import 'package:expr/expr.dart';
import 'rule_config.dart';

/// 响应处理器：解析响应数据，提取列表和字段
class ResponseHandler {
  /// 用 listRule 定位列表容器
  /// data 可以是 Map/List（JSON）或 String（HTML/XML/Text）
  static List<dynamic> extractList(dynamic data, String listRule) {
    // JSON 数组根的直接返回（listRule 为 $ / $. / @Json:$ 时）
    if (data is List &&
        (listRule == r'$' || listRule == r'$.' || listRule == '@Json:\$')) {
      return data;
    }
    initExprEngine();
    // 对 JSON 数据规范化表达式（补 $. 前缀）
    final expr = _normalizeExpr(listRule, data);
    final result = evaluate(expr, data);
    if (result == null) return [];
    if (result is List) return result;
    return [result];
  }

  /// 用 itemRules 提取单个 item 的所有字段
  ///
  /// 支持模板语法：值含 `${expr}` 时按模板求值拼接
  /// 例如 `"${$.server}-${$.id}"` → 先取 server 再取 id，拼成 `netease-12345`
  static Map<String, dynamic> extractItem(dynamic item, Map<String, String> itemRules) {
    initExprEngine();
    final fields = <String, dynamic>{};
    for (final entry in itemRules.entries) {
      final expr = entry.value;
      // 模板语法：含 ${} 的按模板求值
      if (expr.contains(r'${')) {
        final value = _evalTemplate(expr, item);
        if (value.isNotEmpty) {
          fields[entry.key] = value;
        }
        continue;
      }
      // 数据为 Map 时，无前缀的表达式视为 JSONPath（补 $.）
      final normalized = _normalizeExpr(expr, item);
      final value = evaluate(normalized, item);
      if (value != null) {
        fields[entry.key] = value;
      }
    }
    return fields;
  }

  /// 模板求值：将 `${expr}` 逐个求值并替换，剩余文本原样保留
  static String _evalTemplate(String template, dynamic data) {
    return template.replaceAllMapped(
      RegExp(r'\$\{([^}]+)\}'),
      (match) {
        final expr = match.group(1)!;
        final normalized = _normalizeExpr(expr, data);
        final result = evaluate(normalized, data);
        return result?.toString() ?? '';
      },
    );
  }

  /// 根据数据类型规范化表达式
  static String _normalizeExpr(String expr, dynamic data) {
    if (data is! Map && data is! List) return expr;
    // 无前缀的纯标识符 → 补 $. 作为 JSONPath
    if (!expr.startsWith('@') &&
        !expr.startsWith(r'$') &&
        !expr.startsWith('//') &&
        !expr.startsWith(':')) {
      return r'$.' + expr;
    }
    return expr;
  }

  /// 提取分页信息
  ///
  /// [resultCount] 当前页返回的结果数量（size 类型用）
  /// [currentPage] 当前页码（size 类型用，计算 nextPage）
  static Map<String, dynamic>? extractPagination(
    dynamic data,
    PaginationRule? rule, {
    int? resultCount,
    int? currentPage,
  }) {
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
      case 'size':
        // 数量推断：返回数 >= limit → 有下一页
        final limit = rule.limitValue ?? 20;
        final count = resultCount ?? 0;
        final page = currentPage ?? 1;
        if (count >= limit) {
          info['nextPage'] = page + 1;
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