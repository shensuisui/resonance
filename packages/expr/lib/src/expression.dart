/// 解析器类型
enum ParserType {
  css,
  jsonPath,
  xPath,
  regex,
}

/// 复合表达式类型
enum CompoundType {
  /// 单一表达式
  none,

  /// 规则链（&&）：前一条输出作为后一条输入
  chain,

  /// 备用规则（||）：当前规则未匹配时使用备用规则
  fallback,
}

/// 单一解析结果
class ParseResult {
  final ParserType type;
  final String rawExpression;
  final String selector;
  final String? extractSuffix;

  const ParseResult({
    required this.type,
    required this.rawExpression,
    required this.selector,
    this.extractSuffix,
  });

  @override
  String toString() =>
      'ParseResult(type: $type, selector: $selector, extractSuffix: $extractSuffix)';
}

/// 可执行的表达式（解析结果 + 复合/后处理）
class Expression {
  /// 复合表达式的各部分（单一表达式时 parts.length == 1）
  final List<ParseResult> parts;

  /// 复合表达式类型
  final CompoundType compoundType;

  /// 净化修饰符（##）：移除/替换匹配内容
  final String? sanitizePattern;
  final String? sanitizeReplacement;

  /// 分割修饰符（#）：按指定字符分割成列表
  final String? splitChar;

  const Expression({
    required this.parts,
    this.compoundType = CompoundType.none,
    this.sanitizePattern,
    this.sanitizeReplacement,
    this.splitChar,
  });

  bool get isCompound => compoundType != CompoundType.none;
  bool get hasSanitize => sanitizePattern != null;
  bool get hasSplit => splitChar != null;

  @override
  String toString() => 'Expression(parts: ${parts.length}, compound: $compoundType)';
}