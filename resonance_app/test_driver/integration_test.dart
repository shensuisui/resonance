/// Flutter Driver 宿主脚本（integration_test 官方标准入口）
///
/// 配合 flutter drive 使用：
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/ui_v2_smoke_test.dart -d windows
///
/// 同时供 Dart/Flutter MCP 的 flutter_driver_command 驱动界面
/// （app 需以 --dart-define=RESONANCE_DRIVER=1 启动以注册驱动扩展）。
library;

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
