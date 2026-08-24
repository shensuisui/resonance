import 'expression.dart';
import 'evaluators/evaluator_interface.dart';
import 'evaluators/compound_evaluator.dart';
import 'evaluators/css_evaluator.dart';
import 'evaluators/jsonpath_evaluator.dart';
import 'evaluators/xpath_evaluator.dart';
import 'evaluators/regex_evaluator.dart';
import 'parsers/parser_factory.dart';

/// 初始化表达式引擎：注册默认执行器
void initExprEngine() {
  EvaluatorFactory.register(ParserType.css, CssEvaluator());
  EvaluatorFactory.register(ParserType.jsonPath, JsonPathEvaluator());
  EvaluatorFactory.register(ParserType.xPath, XPathEvaluator());
  EvaluatorFactory.register(ParserType.regex, RegexEvaluator());
}

/// 便捷方法：解析并执行表达式
/// 支持高级特性：&&（链）、||（备用）、##（净化）、#（分割）
dynamic evaluate(String expression, dynamic data) {
  final expr = ParserFactory.parse(expression);
  return CompoundEvaluator.evaluate(expr, data);
}