import '../expression.dart';
import 'evaluator_interface.dart';

/// 复合表达式执行器
/// 处理规则链（&&）、备用规则（||）、净化（##）、分割（#）、模板拼接
class CompoundEvaluator {
  /// 执行完整的 Expression，支持复合/后处理
  static dynamic evaluate(Expression expression, dynamic data) {
    // 1. 执行复合表达式（链/备用）
    dynamic result;

    switch (expression.compoundType) {
      case CompoundType.none:
        result = EvaluatorFactory.evaluate(expression.parts.first, data);
        break;

      case CompoundType.chain:
        result = _evaluateChain(expression.parts, data);
        break;

      case CompoundType.fallback:
        result = _evaluateFallback(expression.parts, data);
        break;
    }

    // 2. 后处理：净化
    if (result != null && expression.hasSanitize) {
      result = _sanitize(result, expression.sanitizePattern!, expression.sanitizeReplacement ?? '');
    }

    // 3. 后处理：分割
    if (result != null && expression.hasSplit) {
      result = _split(result, expression.splitChar!);
    }

    return result;
  }

  /// 链式规则：前一条输出作为后一条输入
  static dynamic _evaluateChain(List<ParseResult> parts, dynamic data) {
    dynamic current = data;
    for (final part in parts) {
      // CSS 提取后缀返回列表，链式传递时若只有一个元素则展开为单值
      if (current is List && current.length == 1) {
        current = current.first;
      }
      current = EvaluatorFactory.evaluate(part, current);
      if (current == null) return null;
    }
    return current;
  }

  /// 备用规则：依次尝试，第一个非 null 的返回
  static dynamic _evaluateFallback(List<ParseResult> parts, dynamic data) {
    for (final part in parts) {
      final result = EvaluatorFactory.evaluate(part, data);
      if (result != null) return result;
    }
    return null;
  }

  /// 净化：用正则模式替换匹配内容
  static dynamic _sanitize(dynamic value, String pattern, String replacement) {
    if (value is String) {
      return value.replaceAll(RegExp(pattern), replacement);
    }
    if (value is List) {
      return value.map((e) => e is String ? e.replaceAll(RegExp(pattern), replacement) : e).toList();
    }
    return value;
  }

  /// 分割：按指定字符分割字符串
  static dynamic _split(dynamic value, String delimiter) {
    if (value is String) {
      return value.split(delimiter).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    return value;
  }
}