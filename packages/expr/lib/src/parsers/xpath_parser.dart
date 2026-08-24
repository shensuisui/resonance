import '../expression.dart';

/// XPath 表达式解析器
///
/// 输入示例:
///   "//div[@class='title']/text()"       → selector="//div[@class='title']/text()"
///   "@XPath://div[@class='title']/text()" → selector="//div[@class='title']/text()"
class XPathParser {
  /// 解析 XPath 表达式
  ParseResult parse(String expression) {
    final trimmed = expression.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('XPath expression cannot be empty');
    }

    String selector;

    if (trimmed.startsWith('@XPath:')) {
      selector = trimmed.substring(7).trim();
    } else if (trimmed.startsWith('//')) {
      selector = trimmed;
    } else {
      throw ArgumentError('Invalid XPath expression: $expression');
    }

    if (selector.isEmpty) {
      throw ArgumentError('Invalid XPath expression: $expression');
    }

    return ParseResult(
      type: ParserType.xPath,
      rawExpression: expression,
      selector: selector,
    );
  }
}