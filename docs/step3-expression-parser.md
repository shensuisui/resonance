# Step 3: 表达式解析器

| 步骤 | 3 |
| :--- | :--- |
| 包 | `expr` |
| 依赖 | html, json_path, xml |
| 状态 | 已完成 |

---

## 1. 概述

`expr` 包提供表达式解析与执行抽象层，支持四种表达式类型（CSS 选择器、JSONPath、XPath、正则表达式），以及高级特性（规则链、备用规则、净化、分割）。

每个表达式经历两个阶段：**解析**（String → ParseResult → Expression）→ **执行**（Expression + data → 提取值）。

## 2. 核心抽象

### 2.1 表达式类型

```dart
enum ParserType { css, jsonPath, xPath, regex }
enum CompoundType { none, chain, fallback }
```

### 2.2 ParseResult（单一解析结果）

```dart
class ParseResult {
  final ParserType type;
  final String rawExpression;
  final String selector;
  final String? extractSuffix;  // CSS 提取后缀（@text/@html/@src/@href）
}
```

### 2.3 Expression（可执行表达式）

```dart
class Expression {
  final List<ParseResult> parts;  // 复合表达式的各部分
  final CompoundType compoundType;
  final String? sanitizePattern;
  final String? sanitizeReplacement;
  final String? splitChar;
}
```

## 3. 解析器

### 3.1 CSSParser

| 输入 | selector | extractSuffix |
| :--- | :--- | :--- |
| `div.title` | `div.title` | null |
| `div.title@text` | `div.title` | `@text` |
| `img.cover@src` | `img.cover` | `@src` |
| `a.link@href` | `a.link` | `@href` |

### 3.2 JSONPathParser

| 输入 | selector |
| :--- | :--- |
| `$.data.songs` | `$.data.songs` |
| `@Json:$.data.books[0].title` | `$.data.books[0].title` |

### 3.3 XPathParser

| 输入 | selector |
| :--- | :--- |
| `//div[@class='title']/text()` | `//div[@class='title']/text()` |
| `@XPath://div` | `//div` |

### 3.4 RegexParser

| 输入 | selector |
| :--- | :--- |
| `:title\s*:\s*(.*?)\s*\n` | `title\s*:\s*(.*?)\s*\n` |
| `@Regex:pattern` | `pattern` |

### 3.5 ParserFactory

`ParserFactory.parse()` 返回 `Expression`，按以下优先级处理：

1. `&&` → 链式规则（Chain）
2. `##` → 净化修饰符（Sanitize）
3. `||` → 备用规则（Fallback）
4. `#<delimiter>` → 分割修饰符（Split）
5. 无修饰符 → 单一表达式

## 4. 执行器（Evaluator）

### 4.1 单一执行器

| 执行器 | 使用库 | 输入数据 | 说明 |
| :--- | :--- | :--- | :--- |
| `CssEvaluator` | `html` | HTML 字符串 | CSS 选择器查询，支持 @text/@html/@src/@href 后缀 |
| `JsonPathEvaluator` | `json_path` | Map/List | JSONPath 查询 |
| `XPathEvaluator` | `xml` | XML/HTML 字符串 | 基础 XPath（/、//、[@attr='val']） |
| `RegexEvaluator` | Dart SDK | 纯文本字符串 | 正则匹配，支持捕获组 |

### 4.2 CompoundEvaluator（复合执行器）

处理高级特性：

| 特性 | 语法 | 示例 | 行为 |
| :--- | :--- | :--- | :--- |
| **规则链** | `&&` | `$.data && $.songs` | 前一条输出作为后一条输入 |
| **备用规则** | `||` | `img.cover@src \|\| img.thumb@src` | 依次尝试，第一个非 null 返回 |
| **净化** | `##pattern\|\|replacement` | `div.content##<.*?>\|\|` | 正则替换匹配内容 |
| **分割** | `#<delimiter>` | `div.tags#,` | 按指定字符分割字符串 |

### 4.3 引擎初始化

```dart
void initExprEngine();  // 注册所有默认执行器
dynamic evaluate(String expression, dynamic data);  // 便捷方法：解析并执行
```

## 5. 包结构

```
packages/expr/lib/
├── expr.dart
└── src/
    ├── expression.dart              # ParserType, ParseResult, Expression
    ├── expr_engine.dart             # 引擎初始化 + evaluate()
    ├── parsers/
    │   ├── css_parser.dart
    │   ├── jsonpath_parser.dart
    │   ├── xpath_parser.dart
    │   ├── regex_parser.dart
    │   └── parser_factory.dart
    └── evaluators/
        ├── evaluator_interface.dart
        ├── compound_evaluator.dart  # 链/备用/净化/分割
        ├── css_evaluator.dart
        ├── jsonpath_evaluator.dart
        ├── xpath_evaluator.dart
        └── regex_evaluator.dart
```

## 6. 测试覆盖

| 分组 | 测试数 | 覆盖 |
| :--- | :--- | :--- |
| CSSParser | 3 | 简单选择器、@text 后缀、空表达式 |
| JSONPathParser | 3 | $. 前缀、@Json: 前缀、空后前缀 |
| XPathParser | 2 | // 前缀、@XPath: 前缀 |
| RegexParser | 2 | : 前缀、@Regex: 前缀 |
| ParserFactory | 9 | 各前缀路由、无前缀默认 CSS、空表达式 |
| 高级特性解析 | 6 | && 链、\|\| 备用、## 净化、# 分割 |
| CssEvaluator | 8 | 基本提取、@text 后缀、无匹配、后代/子级/多级选择器、属性选择器、@text 列表 |
| CompoundEvaluator | 11 | JSONPath 链（2）、链返回 null、备用（2）、备用全空、净化（2）、分割、CSS ID 不误判、链+净化组合 |
| JsonPathEvaluator | 1 | Map 中提取 |
| RegexEvaluator | 1 | 捕获组匹配 |
| XPathEvaluator | 1 | 基础 XPath |
| initExprEngine | 1 | 注册全部执行器 |
| **合计** | **50** | |