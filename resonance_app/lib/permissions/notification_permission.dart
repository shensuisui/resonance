/// 请求 Android 13+ 通知权限（后台播放通知/媒体控件可见）
library;

import 'package:flutter/services.dart';

/// 确保通知权限（Android 13+ 弹系统授权；其他平台返回 true）
Future<bool> ensureNotificationPermission() async {
  try {
    final granted = await const MethodChannel('resonance/permissions')
        .invokeMethod<bool>('ensureNotificationPermission');
    return granted ?? true;
  } on MissingPluginException {
    return true;
  } on PlatformException {
    return false;
  }
}
