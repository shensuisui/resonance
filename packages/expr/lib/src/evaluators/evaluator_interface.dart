import '../expression.dart';

/// 表达式执行器接口
abstract class ExpressionEvaluator {
  /// 对 data 执行表达式，返回提取结果
  /// [data] 可以是 String（HTML/XML/纯文本）或 Map/List（JSON）
  /// 返回提取到的值，未匹配时返回 null
  dynamic evaluate(ParseResult result, dynamic data);
}

/// 执行器工厂
class EvaluatorFactory {
  static final Map<ParserType, ExpressionEvaluator> _evaluators = {};

  /// 注册自定义执行器
  static void register(ParserType type, ExpressionEvaluator evaluator) {
    _evaluators[type] = evaluator;
  }

  /// 获取对应类型的执行器
  static ExpressionEvaluator? getEvaluator(ParserType type) {
    return _evaluators[type];
  }

  /// 根据 ParseResult 自动选择并执行
  static dynamic evaluate(ParseResult result, dynamic data) {
    final evaluator = _evaluators[result.type];
    if (evaluator == null) {
      throw UnsupportedError('No evaluator registered for ${result.type}');
    }
    return evaluator.evaluate(result, data);
  }
}