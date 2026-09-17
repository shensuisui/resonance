/// 测试支持：假 PathProvider 平台
///
/// CachedNetworkImage 默认 CacheManager 需要 path_provider 插件，
/// flutter_test 环境无原生实现（MissingPluginException）。
/// 在涉及网络封面图的测试 setUp 中调用 [setupFakePathProvider] 解决。
library;

import 'dart:io';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;

  @override
  Future<String?> getApplicationSupportPath() async =>
      Directory.systemTemp.path;

  @override
  Future<String?> getApplicationDocumentsPath() async =>
      Directory.systemTemp.path;
}

/// 替换 PathProvider 平台实现为内存/系统临时目录（测试用）
void setupFakePathProvider() {
  PathProviderPlatform.instance = _FakePathProvider();
}
