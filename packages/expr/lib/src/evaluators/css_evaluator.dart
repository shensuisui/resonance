import 'package:html/parser.dart' as html_parser;
import '../expression.dart';
import 'evaluator_interface.dart';

/// CSS 选择器执行器
/// 使用 html 包解析 HTML 并执行 CSS 选择器查询
class CssEvaluator implements ExpressionEvaluator {
  @override
  dynamic evaluate(ParseResult result, dynamic data) {
    if (data is! String) {
      throw ArgumentError('CSS evaluator requires HTML string data');
    }

    final document = html_parser.parse(data);
    final elements = document.querySelectorAll(result.selector);

    if (elements.isEmpty) return null;

    // 根据提取后缀处理结果
    final suffix = result.extractSuffix;
    if (suffix != null) {
      switch (suffix) {
        case '@text':
          return elements.map((e) => e.text.trim()).toList();
        case '@html':
          return elements.map((e) => e.innerHtml).toList();
        case '@src':
          return elements.map((e) => e.attributes['src'] ?? '').toList();
        case '@href':
          return elements.map((e) => e.attributes['href'] ?? '').toList();
        case '@attr':
          // 需要从 selector 中提取属性名
          return elements.map((e) => e.attributes.values.firstOrNull ?? '').toList();
        default:
          return elements.map((e) => e.text.trim()).toList();
      }
    }

    // 无后缀：返回首元素的文本
    return elements.first.text.trim();
  }
}