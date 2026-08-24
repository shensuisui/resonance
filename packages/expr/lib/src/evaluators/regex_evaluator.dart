import '../expression.dart';
import 'evaluator_interface.dart';

/// 正则表达式执行器
/// 使用 Dart 内置 RegExp 执行正则匹配
class RegexEvaluator implements ExpressionEvaluator {
  @override
  dynamic evaluate(ParseResult result, dynamic data) {
    if (data is! String) {
      throw ArgumentError('Regex evaluator requires string data');
    }

    final regex = RegExp(result.selector);
    final match = regex.firstMatch(data);

    if (match == null) return null;

    // 如果有捕获组，返回第一个捕获组；否则返回整个匹配
    if (match.groupCount >= 1) {
      return match.group(1);
    }
    return match.group(0);
  }
}