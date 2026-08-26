import 'package:expr/expr.dart';

void main() {
  // 单表达式解析
  final result = ParserFactory.parse('div.title@text');
  print('Parts: ${result.parts.length}, Type: ${result.compoundType}');

  // 链式表达式
  final chain = ParserFactory.parse('div.title@text && @Regex:《([^》]+)》');
  print('Chain parts: ${chain.parts.length}, Type: ${chain.compoundType}');

  // 备用表达式
  final fallback = ParserFactory.parse('div.title@text || div.name@text');
  print('Fallback parts: ${fallback.parts.length}, Type: ${fallback.compoundType}');

  // 求值
  initExprEngine();
  final html = '<div class="title">周杰伦《稻香》</div>';
  final value = evaluate('@CSS:div.title@text', html);
  print('CSS evaluate: $value');

  final regexResult = evaluate('@Regex:《([^》]+)》', '周杰伦《稻香》');
  print('Regex evaluate: $regexResult');
}
