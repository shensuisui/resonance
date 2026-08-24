import '../expression.dart';
import 'css_parser.dart';
import 'jsonpath_parser.dart';
import 'regex_parser.dart';
import 'xpath_parser.dart';

/// 解析器工厂：根据表达式前缀自动识别解析器类型并解析
/// 支持高级特性：&&（链）、||（备用）、##（净化）、#（分割）
class ParserFactory {
  static final CSSParser _cssParser = CSSParser();
  static final JSONPathParser _jsonPathParser = JSONPathParser();
  static final XPathParser _xPathParser = XPathParser();
  static final RegexParser _regexParser = RegexParser();

  /// 解析表达式字符串，返回可执行的 Expression
  /// 支持高级特性：&& 链、|| 备用、## 净化、# 分割
  static Expression parse(String expression) {
    final trimmed = expression.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Expression cannot be empty');
    }

    // 1. 检查是否包含 &&（链式规则）
    if (trimmed.contains('&&')) {
      return _parseChain(trimmed);
    }

    // 2. 检查 ##（净化修饰符）— 必须在 || 之前，因为 ## 语法也包含 ||
    // 格式: 主表达式##<pattern>||<replacement>
    final sanitizeMatch = RegExp(r'##(.+?)\|\|(.*)$').firstMatch(trimmed);
    if (sanitizeMatch != null) {
      final mainExpr = trimmed.substring(0, sanitizeMatch.start).trim();
      final pattern = sanitizeMatch.group(1);
      final replacement = sanitizeMatch.group(2) ?? '';
      if (mainExpr.isEmpty) {
        throw ArgumentError('Sanitize requires a main expression before ##: $trimmed');
      }
      return Expression(
        parts: [_parseSingle(mainExpr)],
        sanitizePattern: pattern,
        sanitizeReplacement: replacement,
      );
    }

    // 3. 检查 ||（备用规则）
    if (trimmed.contains('||')) {
      return _parseFallback(trimmed);
    }

    // 4. 检查 #（分割修饰符）— 仅匹配末尾的 #<非字母字符>
    final splitMatch = RegExp(r'#([^a-zA-Z0-9])$').firstMatch(trimmed);
    if (splitMatch != null) {
      final mainExpr = trimmed.substring(0, splitMatch.start).trim();
      final splitChar = splitMatch.group(1);
      if (mainExpr.isEmpty) {
        throw ArgumentError('Split requires a main expression before #: $trimmed');
      }
      return Expression(
        parts: [_parseSingle(mainExpr)],
        splitChar: splitChar,
      );
    }

    // 5. 单一表达式
    return Expression(parts: [_parseSingle(trimmed)]);
  }

  /// 解析链式规则：expr1 && expr2 && expr3
  static Expression _parseChain(String trimmed) {
    final rawParts = trimmed.split('&&').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (rawParts.length < 2) {
      throw ArgumentError('Chain expression must have at least 2 parts: $trimmed');
    }
    // 每个部分单独解析（支持 ##、# 等修饰符）
    final subExprs = rawParts.map((s) => parse(s)).toList();
    final allParts = subExprs.expand((e) => e.parts).toList();
    // 后处理修饰符取自最后一部分
    final last = subExprs.last;
    return Expression(
      parts: allParts,
      compoundType: CompoundType.chain,
      sanitizePattern: last.sanitizePattern,
      sanitizeReplacement: last.sanitizeReplacement,
      splitChar: last.splitChar,
    );
  }

  /// 解析备用规则：expr1 || expr2
  static Expression _parseFallback(String trimmed) {
    final rawParts = trimmed.split('||').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (rawParts.length < 2) {
      throw ArgumentError('Fallback expression must have at least 2 parts: $trimmed');
    }
    // 每个部分单独解析（支持 ##、# 等修饰符）
    final subExprs = rawParts.map((s) => parse(s)).toList();
    final allParts = subExprs.expand((e) => e.parts).toList();
    // 后处理修饰符取自最后一部分
    final last = subExprs.last;
    return Expression(
      parts: allParts,
      compoundType: CompoundType.fallback,
      sanitizePattern: last.sanitizePattern,
      sanitizeReplacement: last.sanitizeReplacement,
      splitChar: last.splitChar,
    );
  }

  /// 解析单一表达式
  static ParseResult _parseSingle(String trimmed) {
    // 按优先级识别前缀
    if (trimmed.startsWith('@XPath:')) {
      return _xPathParser.parse(trimmed);
    }
    if (trimmed.startsWith('@Json:')) {
      return _jsonPathParser.parse(trimmed);
    }
    if (trimmed.startsWith('@CSS:')) {
      return _cssParser.parse(trimmed.substring(5).trim());
    }
    if (trimmed.startsWith('@Regex:')) {
      return _regexParser.parse(trimmed);
    }
    if (trimmed.startsWith(r'$.')) {
      return _jsonPathParser.parse(trimmed);
    }
    if (trimmed.startsWith('//')) {
      return _xPathParser.parse(trimmed);
    }
    if (trimmed.startsWith(':')) {
      return _regexParser.parse(trimmed);
    }
    // 无前缀，默认 CSS 选择器
    return _cssParser.parse(trimmed);
  }
}