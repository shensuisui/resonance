/// 通知权限封装的降级测试（无平台实现时不应阻塞）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:resonance_app/permissions/notification_permission.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('无平台实现时返回 true（非 Android / 测试环境）', () async {
    expect(await ensureNotificationPermission(), isTrue);
  });
}
