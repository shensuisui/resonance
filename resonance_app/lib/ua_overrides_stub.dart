/// Web 平台浏览器 UA 处理（no-op）
///
/// 浏览器自行控制 User-Agent 请求头，Dart 侧无法也不应修改。
library;

void applyBrowserUserAgent() {
  // no-op：a browsers control the User-Agent header
}