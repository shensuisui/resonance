import 'package:expr/expr.dart';
import 'package:test/test.dart';

void main() {
  group('evaluate convenience', () {
    setUp(() {
      initExprEngine();
    });

    test('CSS expression', () {
      final html = '<html><body><div class="title">Hello</div></body></html>';
      final result = evaluate('div.title', html);
      expect(result, 'Hello');
    });

    test('JSONPath expression', () {
      final data = {'id': '123', 'name': 'Test'};
      final result = evaluate(r'$.name', data);
      expect(result, 'Test');
    });
  });
}