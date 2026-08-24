import '../expression.dart';

/// JSONPath 表达式解析器
///
/// 输入示例:
///   "$.data.songs"              → selector="$.data.songs"
///   "@Json:$.data.books[0].title" → selector="$.data.books[0].title"
class JSONPathParser {
  /// 解析 JSONPath 表达式
  ParseResult parse(String expression) {
    final trimmed = expression.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('JSONPath expression cannot be empty');
    }

    String selector;

    if (trimmed.startsWith('@Json:')) {
      selector = trimmed.substring(6).trim();
    } else if (trimmed.startsWith(r'$.')) {
      selector = trimmed;
    } else {
      // 没有明确前缀，仍按 JSONPath 处理
      selector = trimmed;
    }

    if (selector.isEmpty) {
      throw ArgumentError('Invalid JSONPath expression: $expression');
    }

    return ParseResult(
      type: ParserType.jsonPath,
      rawExpression: expression,
      selector: selector,
    );
  }
}