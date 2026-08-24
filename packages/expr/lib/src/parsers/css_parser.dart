import '../expression.dart';

/// CSS 选择器解析器
///
/// 输入示例:
///   "div.title@text"  → selector="div.title", extractSuffix="@text"
///   ".cover@src"      → selector=".cover", extractSuffix="@src"
///   "h1"              → selector="h1", extractSuffix=null
class CSSParser {
  /// 解析 CSS 选择器表达式
  ParseResult parse(String expression) {
    final trimmed = expression.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('CSS expression cannot be empty');
    }

    String? extractSuffix;

    // 检查 @text / @html / @attr 后缀
    final suffixMatch = RegExp(r'@(text|html|attr|src|href)$').firstMatch(trimmed);
    if (suffixMatch != null) {
      extractSuffix = '@${suffixMatch.group(1)}';
    }

    final selector = extractSuffix != null
        ? trimmed.substring(0, trimmed.length - extractSuffix.length)
        : trimmed;

    return ParseResult(
      type: ParserType.css,
      rawExpression: expression,
      selector: selector.trim(),
      extractSuffix: extractSuffix,
    );
  }
}