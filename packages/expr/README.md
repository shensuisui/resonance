# expr — 表达式解析与执行

纯 Dart 包，为规则引擎提供多格式表达式的解析与执行。

## 职责
- Parser：CSS / JSONPath / XPath / Regex。
- 复合表达式：chain（&&）、fallback（||）、净化（##）、分割（#）。
- ParserFactory 自动路由；Evaluator 负责求值。
- @JS:（JavaScript）为预研项，当前不支持。

## 依赖
html、xml、json_path。

## 测试
在 packages/expr 下运行 dart test。
