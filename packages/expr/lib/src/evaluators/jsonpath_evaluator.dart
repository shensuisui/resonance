import 'package:json_path/json_path.dart';
import '../expression.dart';
import 'evaluator_interface.dart';

/// JSONPath 执行器
/// 使用 json_path 包执行 JSONPath 查询
class JsonPathEvaluator implements ExpressionEvaluator {
  @override
  dynamic evaluate(ParseResult result, dynamic data) {
    if (data is! Map && data is! List) {
      throw ArgumentError('JSONPath evaluator requires Map or List data');
    }

    final jsonPath = JsonPath(result.selector);
    final matches = jsonPath.read(data);

    if (matches.isEmpty) return null;

    // 返回所有匹配值，若只有一个则直接返回值
    final values = matches.map((m) => m.value).toList();
    return values.length == 1 ? values.first : values;
  }
}