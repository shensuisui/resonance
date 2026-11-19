/// 网络类型判定（仅 Wi-Fi 自动同步用）
library;

import 'package:connectivity_plus/connectivity_plus.dart';

/// 当前是否在 Wi-Fi 上
///
/// 说明：connectivity_plus 6.x 的 checkConnectivity 返回 List<ConnectivityResult>。
/// 有线/以太网在桌面视为可用（等价 Wi-Fi 的「非计费网络」语义）。
Future<bool> isOnWifi() async {
  final results = await Connectivity().checkConnectivity();
  return results.contains(ConnectivityResult.wifi) ||
      results.contains(ConnectivityResult.ethernet);
}
