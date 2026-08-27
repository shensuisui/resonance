/// 浏览器 User-Agent 替换 —— 平台条件导入入口
///
/// dart:io 平台全局替换默认 UA（网易等 CDN 对 Dart UA 做访问控制，返回 403）；
/// Web 平台浏览器控制 UA，为 no-op。
library;

import 'ua_overrides_stub.dart'
    if (dart.library.io) 'ua_overrides_io.dart' as impl;

/// 全局替换 dart:io 默认 User-Agent 为浏览器 UA
void applyBrowserUserAgent() => impl.applyBrowserUserAgent();