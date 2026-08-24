# Step 2: 创建 crawler 包 + HTTP 封装

| 步骤 | 2 |
| :--- | :--- |
| 包 | `crawler` |
| 依赖 | core, expr, dio |
| 状态 | 待实现 |

---

## 1. 概述

创建 `crawler` 包，提供远程源实现的 HTTP 请求封装。支持 GET/POST、自定义请求头、URL 占位符替换。

## 2. HttpClient 封装

```dart
class HttpClient {
  /// 发送 GET 请求
  Future<HttpResponse> get(String url, {Map<String, String>? headers});

  /// 发送 POST 请求
  Future<HttpResponse> post(String url, {Map<String, String>? headers, dynamic body});

  /// 替换 URL 中的占位符 {key} -> value
  static String resolveUrl(String url, Map<String, String> placeholders);
}

class HttpResponse {
  final dynamic data;     // 解析后的响应数据（Map/List 或 String）
  final String rawData;  // 原始响应字符串
  final int statusCode;
  final String responseType;  // json / html / text
}
```

### 占位符替换

`resolveUrl` 支持替换 `{key}` 格式的占位符：

| 占位符 | 说明 |
| :--- | :--- |
| `{baseUrl}` | 源的基础 URL |
| `{keyword}` | 搜索关键词 |
| `{page}` | 页码 |
| `{id}` | 歌曲/歌单 ID |
| `{lyricUrl}` | 歌词 URL |

## 3. 包结构

```
packages/crawler/lib/
├── crawler.dart
└── src/
    └── http/
        └── http_client.dart
```

## 4. 测试用例

- GET 请求发送与响应解析
- POST 请求发送
- 占位符替换正确性
- 自定义请求头