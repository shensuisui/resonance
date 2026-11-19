/// 云同步状态与动作（uiv2 侧）
///
/// 只依赖 [SyncService] 契约；具体实现由壳工程 override。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/sync_service.dart';

/// 壳工程注入的同步服务
final syncServiceProvider = Provider<SyncService>(
  (ref) => throw UnimplementedError('syncServiceProvider 必须被壳工程覆盖'),
  name: 'syncServiceProvider',
);

/// 当前同步状态（Async，承载加载/错误）
final syncStatusProvider =
    AsyncNotifierProvider<SyncStatusNotifier, SyncStatusView>(
  SyncStatusNotifier.new,
  name: 'syncStatusProvider',
);

/// 状态与动作封装
class SyncStatusNotifier extends AsyncNotifier<SyncStatusView> {
  SyncService get _service => ref.read(syncServiceProvider);

  @override
  Future<SyncStatusView> build() => _service.loadStatus();

  /// 重新读取状态
  Future<void> refresh() async {
    state = await AsyncValue.guard(_service.loadStatus);
  }

  /// 保存凭据并开启
  Future<SyncActionResult> saveAndEnable({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final result = await _service.saveAndEnable(
      baseUrl: baseUrl,
      username: username,
      password: password,
    );
    await refresh();
    return result;
  }

  /// 测试连接
  Future<SyncActionResult> testConnection({
    required String baseUrl,
    required String username,
    required String password,
  }) =>
      _service.testConnection(
        baseUrl: baseUrl,
        username: username,
        password: password,
      );

  /// 开关
  Future<SyncActionResult> setEnabled(bool enabled) async {
    final result = await _service.setEnabled(enabled);
    await refresh();
    return result;
  }

  /// 立即同步
  Future<SyncActionResult> syncNow() async {
    final result = await _service.syncNow();
    await refresh();
    return result;
  }

  /// 历史版本
  Future<List<SyncVersionView>> loadVersions() => _service.loadVersions();

  /// 回滚
  Future<SyncActionResult> restoreVersion(int version) async {
    final result = await _service.restoreVersion(version);
    await refresh();
    return result;
  }

  /// 重置
  Future<SyncActionResult> reset() async {
    final result = await _service.reset();
    await refresh();
    return result;
  }
}
