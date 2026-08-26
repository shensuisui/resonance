/// Web 平台的 JsRuntime stub
///
/// Web 不支持 flutter_inappwebview，JS 插件运行时不可用。
/// 所有实例方法抛 UnsupportedError，create() 返回 null。
/// 规则引擎源（RuleBasedMusicSource）在 Web 上正常工作。

import '../http/http_client.dart';

/// JS 运行时（Web stub）
class JsRuntime {
  JsRuntime({HttpClient? httpClient});

  /// 创建 JsRuntime 实例
  /// Web 平台返回 null（不支持 JS 插件）
  static Future<JsRuntime?> create() async => null;

  /// 加载插件 JS——Web 不支持
  Future<bool> loadPlugin(String jsContent) async {
    throw UnsupportedError('Web 平台不支持 JS 插件运行时');
  }

  /// 插件是否已加载——Web 返回 false
  Future<bool> get isPluginLoaded async => false;

  /// 检查函数是否存在——Web 返回 false
  Future<bool> hasFunction(String name) async => false;

  /// 调用插件函数——Web 不支持
  Future<dynamic> callPluginFunction(String funcName, List<dynamic> args) async {
    throw UnsupportedError('Web 平台不支持 JS 插件运行时');
  }

  /// 释放资源——Web 无操作
  Future<void> dispose() async {}
}
