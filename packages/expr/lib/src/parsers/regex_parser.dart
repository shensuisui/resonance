import '../expression.dart';

/// 正则表达式解析器
///
/// 输入示例:
///   ":title\s*:\s*(.*?)\s*\n"           → selector="title\s*:\s*(.*?)\s*\n"
///   "@Regex:title\s*:\s*(.*?)\s*\n"      → selector="title\s*:\s*(.*?)\s*\n"
class RegexParser {
  /// 解析正则表达式
  ParseResult parse(String expression) {
    final trimmed = expression.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Regex expression cannot be empty');
    }

    String selector;

    if (trimmed.startsWith('@Regex:')) {
      selector = trimmed.substring(7).trim();
    } else if (trimmed.startsWith(':')) {
      selector = trimmed.substring(1).trim();
    } else {
      throw ArgumentError('Invalid regex expression: $expression');
    }

    if (selector.isEmpty) {
      throw ArgumentError('Invalid regex expression: $expression');
    }

    return ParseResult(
      type: ParserType.regex,
      rawExpression: expression,
      selector: selector,
    );
  }
}