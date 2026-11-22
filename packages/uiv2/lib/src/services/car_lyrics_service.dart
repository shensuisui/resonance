/// 车载蓝牙状态契约（由壳工程注入实现）
///
/// uiv2 只消费「蓝牙是否已连 / 是否识别为车机」，平台细节在壳工程。
library;

/// 当前蓝牙/车机状态
class CarLyricsDeviceState {
  /// 是否已连接蓝牙音频
  final bool bluetoothConnected;

  /// 是否识别为车机（iOS carAudio / Android CAR_AUDIO）
  final bool carDetected;

  /// 设备名（可空，仅展示/调试）
  final String? deviceName;

  /// 构造
  const CarLyricsDeviceState({
    this.bluetoothConnected = false,
    this.carDetected = false,
    this.deviceName,
  });

  /// 从平台通道 Map 解析（缺字段按 false）
  factory CarLyricsDeviceState.fromMap(Map<Object?, Object?> map) =>
      CarLyricsDeviceState(
        bluetoothConnected: map['bluetoothConnected'] == true,
        carDetected: map['carDetected'] == true,
        deviceName: map['deviceName'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is CarLyricsDeviceState &&
      other.bluetoothConnected == bluetoothConnected &&
      other.carDetected == carDetected &&
      other.deviceName == deviceName;

  @override
  int get hashCode => Object.hash(bluetoothConnected, carDetected, deviceName);

  @override
  String toString() =>
      'CarLyricsDeviceState(bt: $bluetoothConnected, car: $carDetected, name: $deviceName)';
}

/// 车载蓝牙状态能力
abstract interface class CarLyricsService {
  /// 状态变化流（路由/连接变化时推送）
  Stream<CarLyricsDeviceState> get stream;

  /// 当前状态（首次读取用）
  Future<CarLyricsDeviceState> current();

  /// 确保已获得蓝牙相关权限（Android 12+ BLUETOOTH_CONNECT；iOS 无操作）
  Future<void> ensurePermission();
}
