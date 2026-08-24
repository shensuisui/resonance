# Step 3: 规则执行引擎

| 步骤 | 3 |
| :--- | :--- |
| 包 | `crawler` |
| 依赖 | core（数据模型）, expr（表达式解析执行）, http（HTTP 封装） |
| 状态 | 待实现 |

---

## 1. 概述

规则执行引擎是 `crawler` 包的核心，负责加载规则配置、执行搜索/详情/歌词/歌单等流程。核心类：`RuleExecutor`、`ResponseHandler`、`RuleLoader`。

## 2. 数据模型

### 2.1 RuleConfig

```dart
class RuleConfig {
  final SourceInfo source;
  final SearchRule? search;
  final DetailRule? songDetail;
  final LyricRule? lyric;
  final PlaylistRule? playlist;
}

class SearchRule {
  final String url;
  final String method;
  final Map<String, String> headers;
  final String responseType;  // json / html / text
  final String listRule;      // 定位列表容器
  final Map<String, String> itemRules;  // 字段 -> 表达式
  final PaginationRule? pagination;
}

class DetailRule {
  final String url;
  final String method;
  final Map<String, String> headers;
  final String responseType;
  final String listRule;
  final Map<String, String> itemRules;
}

class LyricRule {
  final String url;
  final String method;
  final Map<String, String> headers;
  final String responseType;
  final String? listRule;
  final String? contentRule;
}

class PlaylistRule {
  final String url;
  final String method;
  final Map<String, String> headers;
  final String responseType;
  final String listRule;
  final Map<String, String> itemRules;
  final PaginationRule? pagination;
}

class PaginationRule {
  final String type;  // page / offset / cursor
  final String? pageParam;
  final String? offsetParam;
  final String? limitParam;
  final int? limitValue;
  final String? cursorParam;
  final String? cursorRule;
  final String? totalRule;
  final String? totalRegex;
}
```

### 2.2 RuleLoader

从 JSON 字符串加载规则配置：

```dart
class RuleLoader {
  static RuleConfig? loadFromJson(String jsonString);
  static RuleConfig? loadFromFile(String filePath);
  static List<RuleConfig> loadAllFromDirectory(String dirPath);
}
```

## 3. RuleExecutor

执行规则流程的核心类：

```dart
class RuleExecutor {
  final RuleConfig _rule;
  final HttpClient _httpClient;

  RuleExecutor(this._rule, {HttpClient? httpClient});

  /// 执行搜索
  Future<SearchResult> executeSearch(String keyword, {int page = 1});

  /// 获取歌曲详情
  Future<Map<String, dynamic>> executeSongDetail(String id);

  /// 获取歌词
  Future<String?> executeLyric(String id, {String? lyricUrl});

  /// 获取歌单
  Future<SearchResult> executePlaylist(String id);
}
```

### 执行流程

1. **构建 URL**：用 `HttpClient.resolveUrl` 替换占位符
2. **发送请求**：GET/POST + headers
3. **处理响应**：根据 responseType 解析
4. **定位列表**：用 listRule 表达式提取容器
5. **提取字段**：对每个 item 用 itemRules 表达式提取各字段
6. **处理分页**：提取下一页/游标信息

## 4. ResponseHandler

```dart
class ResponseHandler {
  /// 根据 responseType 解析响应数据
  static dynamic parseData(HttpResponse response);

  /// 用 listRule 定位列表容器
  static List<dynamic> extractList(dynamic data, String listRule);

  /// 用 itemRules 提取单个 item 的字段
  static Map<String, dynamic> extractItem(dynamic item, Map<String, String> itemRules);

  /// 提取分页信息
  static Map<String, dynamic>? extractPagination(dynamic data, PaginationRule? rule);
}
```

## 5. 包结构

```
packages/crawler/lib/
├── crawler.dart
└── src/
    ├── http/
    │   └── http_client.dart      # 已有
    ├── engine/
    │   ├── rule_config.dart       # RuleConfig 数据模型
    │   ├── rule_loader.dart       # 从 JSON 加载
    │   ├── rule_executor.dart     # 执行引擎
    │   └── response_handler.dart  # 响应处理
    └── adapters/                  # 后续步骤
```

## 6. 测试用例

- RuleLoader：从 JSON 字符串加载完整的规则配置
- RuleExecutor：搜索流程（mock HTTP 响应）
- RuleExecutor：详情获取
- ResponseHandler：HTML 响应中提取列表
- ResponseHandler：JSON 响应中提取列表
- ResponseHandler：itemRules 字段提取
- 分页信息提取（page/offset/cursor）