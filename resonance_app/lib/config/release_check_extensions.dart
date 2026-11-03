/// 发版前集成检查用的 debug-only 服务扩展。
///
/// 为什么不用 flutter_driver：Flan 已经接管驱动层（元素枚举 / 手势 / 截图 / 日志 / 热重载），
/// 它唯一不提供的是「App 内部状态回读」（当前路由、当前曲目、主题、歌词开关…）。
/// skill 的设计就是「MCP 走能力，MCP 没有的走 VM service 服务扩展」，所以这里注册：
///
///   * ext.flutter.releasecheck.state —— 回读 UI 状态（JSON）
///   * ext.flutter.releasecheck.cmd   —— 复用命令路由（navigate / theme / currentSong …）
///
/// 只在 main() 的 kDebugMode 分支里调用；release 由常量分支树摇剔除。
/// 用 dart:developer.registerExtension 而不是 BindingBase.registerServiceExtension：
/// 后者标了 @protected，只能从 Binding 子类里调；前者是它包装的同一个底层 API。
library;

import 'dart:convert';
import 'dart:developer' as developer;

/// 命令路由：由壳工程注入（复用 main_v2 里的 _driverCommand）
typedef ReleaseCheckCommandRunner = Future<String?> Function(
    String cmd, Map<String, String> params);

/// 注册两个扩展
void registerReleaseCheckExtensions({
  required ReleaseCheckCommandRunner runCommand,
}) {
  developer.registerExtension(
    'ext.flutter.releasecheck.state',
    (method, params) async {
      try {
        final raw = await runCommand('state', const <String, String>{});
        return developer.ServiceExtensionResponse.result(raw ?? '{}');
      } catch (e) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          'state 回读失败: $e',
        );
      }
    },
  );

  developer.registerExtension(
    'ext.flutter.releasecheck.cmd',
    (method, params) async {
      try {
        final raw = await runCommand(params['cmd'] ?? '', params);
        return developer.ServiceExtensionResponse.result(
          jsonEncode({'result': raw ?? ''}),
        );
      } catch (e) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          'cmd 执行失败: $e',
        );
      }
    },
  );
}
