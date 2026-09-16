/// Web 平台的 JsRuntime stub
///
/// Web 不支持 flutter_inappwebview，JS 插件运行时不可用。
/// 所有实例方法抛 UnsupportedError，create() 返回 null。
/// 规则引擎源（RuleBasedMusicSource）在 Web 上正常工作。
///
/// 注意：本 stub 的公开接口必须与 IO 版（js_runtime.dart）保持完全一致，
/// 二者经条件导入切换，接口漂移会导致编译失败（此前 callPluginFunction
/// 签名与 isPluginLoaded 形态不一致已引发）。
library;

import '../http/http_client.dart';

/// JS 运行时（Web stub）
class JsRuntime {
  JsRuntime({HttpClient? httpClient});

  /// 是否已初始化——Web 始终 false
  bool get isInitialized => false;

  /// 初始化运行时——Web 不支持
  Future<void> init() async {
    throw UnsupportedError('Web 平台不支持 JS 插件运行时');
  }

  /// 加载插件 JS——Web 不支持
  Future<void> loadPlugin(String pluginJs) async {
    throw UnsupportedError('Web 平台不支持 JS 插件运行时');
  }

  /// 插件是否已加载——Web 返回 false
  Future<bool> isPluginLoaded() async => false;

  /// 检查函数是否存在——Web 返回 false
  Future<bool> hasFunction(String name) async => false;

  /// 调用插件函数——Web 不支持
  ///
  /// 签名与 IO 版一致：[functionExpr] 为 JS 函数调用表达式（含参数）。
  Future<String?> callPluginFunction(String functionExpr) async {
    throw UnsupportedError('Web 平台不支持 JS 插件运行时');
  }

  /// 释放资源——Web 无操作
  Future<void> dispose() async {}
}