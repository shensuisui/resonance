/// 车载蓝牙状态解析与降级测试
///
/// 平台通道在测试环境没有实现：验证 fromMap 解析，以及 current() 降级为“未连接”。

import 'package:flutter_test/flutter_test.dart';
import 'package:resonance_app/car_lyrics/car_lyrics_service.dart';
import 'package:uiv2/uiv2.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fromMap：完整/缺省字段', () {
    final a = CarLyricsDeviceState.fromMap(<Object?, Object?>{
      'bluetoothConnected': true,
      'carDetected': true,
      'deviceName': 'My Car',
    });
    expect(a.bluetoothConnected, isTrue);
    expect(a.carDetected, isTrue);
    expect(a.deviceName, 'My Car');

    final b = CarLyricsDeviceState.fromMap(const <Object?, Object?>{});
    expect(b.bluetoothConnected, isFalse);
    expect(b.carDetected, isFalse);
    expect(b.deviceName, isNull);
  });

  test('current() 在无平台实现时降级为未连接（不抛异常）', () async {
    final service = ShellCarLyricsService();
    final state = await service.current();
    expect(state.bluetoothConnected, isFalse);
    expect(state.carDetected, isFalse);
  });

  test('ensurePermission() 在无平台实现时不抛异常', () async {
    final service = ShellCarLyricsService();
    await service.ensurePermission();
  });
}
