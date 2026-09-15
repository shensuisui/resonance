/// Expression / ParseResult 数据模型单元测试
///
/// 对应 lib/src/expression.dart。
/// parsers_test.dart 验证的是「解析流程产出正确的 Expression」，
/// 本文件直接构造 Expression，验证其辅助 getter 的语义：
/// - isCompound：compoundType != none 时为 true（chain/fallback）
/// - hasSanitize：设置了净化模式（##）时为 true
/// - hasSplit：设置了分割符（#）时为 true
/// - 默认构造（单一表达式、无修饰符）时三者均为 false
/// - toString 包含关键信息（调试日志可读性）
///
/// 无外部依赖，全部用 const 构造的内存数据。
library;

import 'package:expr/expr.dart';
import 'package:test/test.dart';

void main() {
  /// 构造一个最简单的单一 ParseResult（测试数据与解析器无关）
  const cssPart = ParseResult(
    type: ParserType.css,
    rawExpression: 'div.title',
    selector: 'div.title',
  );

  group('ParseResult', () {
    test('保存类型、原始表达式、选择器和提取后缀', () {
      const result = ParseResult(
        type: ParserType.jsonPath,
        rawExpression: r'@Json:$.data',
        selector: r'$.data',
        extractSuffix: '@text',
      );
      expect(result.type, ParserType.jsonPath);
      expect(result.rawExpression, r'@Json:$.data');
      expect(result.selector, r'$.data');
      expect(result.extractSuffix, '@text');
    });

    test('extractSuffix 默认为 null', () {
      expect(cssPart.extractSuffix, isNull);
    });

    test('toString 包含类型和选择器（日志可读性）', () {
      expect(cssPart.toString(), contains('css'));
      expect(cssPart.toString(), contains('div.title'));
    });
  });

  group('Expression 辅助 getter', () {
    test('默认构造：单一表达式，无复合/净化/分割', () {
      const expr = Expression(parts: [cssPart]);
      expect(expr.compoundType, CompoundType.none);
      expect(expr.isCompound, isFalse);
      expect(expr.hasSanitize, isFalse);
      expect(expr.hasSplit, isFalse);
      expect(expr.sanitizePattern, isNull);
      expect(expr.sanitizeReplacement, isNull);
      expect(expr.splitChar, isNull);
    });

    test('chain 复合类型 → isCompound 为 true', () {
      final expr = Expression(
        parts: const [cssPart, cssPart],
        compoundType: CompoundType.chain,
      );
      expect(expr.isCompound, isTrue);
    });

    test('fallback 复合类型 → isCompound 为 true', () {
      final expr = Expression(
        parts: const [cssPart, cssPart],
        compoundType: CompoundType.fallback,
      );
      expect(expr.isCompound, isTrue);
    });

    test('设置净化模式 → hasSanitize 为 true', () {
      const expr = Expression(
        parts: [cssPart],
        sanitizePattern: '<.*?>',
        sanitizeReplacement: '',
      );
      expect(expr.hasSanitize, isTrue);
      expect(expr.hasSplit, isFalse, reason: '净化与分割互相独立');
    });

    test('仅设置净化模式（无替换值）也算 hasSanitize', () {
      // 边界：sanitizeReplacement 为 null（##pattern 后无 || 替换段）
      const expr = Expression(parts: [cssPart], sanitizePattern: 'old');
      expect(expr.hasSanitize, isTrue);
      expect(expr.sanitizeReplacement, isNull);
    });

    test('设置分割符 → hasSplit 为 true', () {
      const expr = Expression(parts: [cssPart], splitChar: ',');
      expect(expr.hasSplit, isTrue);
      expect(expr.hasSanitize, isFalse, reason: '分割与净化互相独立');
    });

    test('空字符串分割符也算 hasSplit（边界）', () {
      // splitChar 判定依据是 != null 而非 isNotEmpty
      const expr = Expression(parts: [cssPart], splitChar: '');
      expect(expr.hasSplit, isTrue);
    });

    test('toString 包含部分数量和复合类型（日志可读性）', () {
      final expr = Expression(
        parts: const [cssPart, cssPart],
        compoundType: CompoundType.chain,
      );
      expect(expr.toString(), contains('2'));
      expect(expr.toString(), contains('chain'));
    });
  });

  group('枚举完整性', () {
    test('ParserType 覆盖四种解析器', () {
      expect(ParserType.values, [
        ParserType.css,
        ParserType.jsonPath,
        ParserType.xPath,
        ParserType.regex,
      ]);
    });

    test('CompoundType 覆盖 none/chain/fallback', () {
      expect(CompoundType.values, [
        CompoundType.none,
        CompoundType.chain,
        CompoundType.fallback,
      ]);
    });
  });
}
