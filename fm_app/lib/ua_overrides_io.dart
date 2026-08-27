/// dart:io 平台的浏览器 User-Agent 替换
///
/// dart:io 的 [HttpClient] 在发送请求时会无条件追加默认 User-Agent
/// （"Dart/<version> (dart:io)"）。网易等 CDN 按 UA 做访问控制——Dart UA 返回
/// 403 + "ua_acl.access"。注意给单个请求设置 User-Agent 头是**追加**而非替换，
/// 无法规避；必须通过 HttpOverrides 全局替换默认值。
library;

import 'dart:io';

/// 浏览器 UA 覆盖：全局替换 dart:io 默认 User-Agent
class _BrowserUaHttpOverrides extends HttpOverrides {
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.userAgent = _ua;
    return client;
  }
}

/// 全局替换默认 User-Agent（应用启动最早阶段调用一次）
void applyBrowserUserAgent() {
  HttpOverrides.global = _BrowserUaHttpOverrides();
}