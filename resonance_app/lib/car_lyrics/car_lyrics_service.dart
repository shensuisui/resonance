/// 壳工程实现：车载蓝牙状态（Android/iOS 平台通道）
///
/// 平台通道：
///   * MethodChannel resonance/car_lyrics：current / ensurePermission
///   * EventChannel resonance/car_lyrics_events：路由或连接变化时推送
library;

import 'package:flutter/services.dart';
import 'package:uiv2/uiv2.dart';

/// 平台通道实现
class ShellCarLyricsService implements CarLyricsService {
  static const MethodChannel _method = MethodChannel('resonance/car_lyrics');
  static const EventChannel _events = EventChannel('resonance/car_lyrics_events');

  Stream<CarLyricsDeviceState>? _stream;

  @override
  Stream<CarLyricsDeviceState> get stream => _stream ??= _events
      .receiveBroadcastStream()
      .map((event) => CarLyricsDeviceState.fromMap(
            (event as Map).cast<Object?, Object?>(),
          ))
      .asBroadcastStream();

  @override
  Future<CarLyricsDeviceState> current() async {
    try {
      final map = await _method.invokeMethod<Map<Object?, Object?>>('current');
      return CarLyricsDeviceState.fromMap(map ?? const <Object?, Object?>{});
    } on MissingPluginException {
      return const CarLyricsDeviceState();
    } on PlatformException {
      return const CarLyricsDeviceState();
    }
  }

  @override
  Future<void> ensurePermission() async {
    try {
      await _method.invokeMethod<void>('ensurePermission');
    } on MissingPluginException {
      // 桌面/测试环境无实现：忽略
    } on PlatformException {
      // 用户拒绝等：静默（功能降级为不注入）
    }
  }
}
