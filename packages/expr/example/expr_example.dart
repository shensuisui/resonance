import 'package:expr/expr.dart';

void main() {
  final result = ParserFactory.parse('div.title@text');
  print('Type: ${result.type}, Selector: ${result.selector}');
}