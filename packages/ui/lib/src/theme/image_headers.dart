/// 网络图片请求头
///
/// 网易等 CDN 会对 Dart 默认 User-Agent（"Dart/x.y (dart:io)"）做访问控制
/// （返回 403 + ua_acl.access），因此所有封面图片需携带浏览器 UA。
library;

const Map<String, String> kImageHeaders = {
  'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
};