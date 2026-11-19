/// 云同步契约（由壳工程注入实现）
///
/// 为什么抽出来：uiv2 是纯 UI 包，不依赖 sync / webdav / 安全存储。
/// 设置页只消费下面的视图模型与动作，平台与引擎细节由 resonance_app 注入。
library;

/// 同步总体状态
enum SyncPhase {
  /// 未配置（没有凭据）
  unconfigured,

  /// 已配置但用户关闭了开关
  disabled,

  /// 空闲（上次成功）
  idle,

  /// 正在同步
  syncing,

  /// 上次同步成功但有冲突
  conflict,

  /// 上次同步失败
  error,
}

/// 一条冲突明细（只读展示）
class SyncConflictView {
  /// 实体名（歌单/收藏/设置…）
  final String entity;

  /// 记录键（歌单名 / 设置键 / song_key）
  final String key;

  /// 本机侧最后修改时间
  final DateTime localAt;

  /// 远端侧最后修改时间
  final DateTime remoteAt;

  /// 构造
  const SyncConflictView({
    required this.entity,
    required this.key,
    required this.localAt,
    required this.remoteAt,
  });
}

/// 云同步状态视图
class SyncStatusView {
  /// 总体阶段
  final SyncPhase phase;

  /// 远端展示名（坚果云 / Nextcloud / 域名）
  final String? remoteLabel;

  /// 本机已知版本
  final int? localVersion;

  /// 远端版本
  final int? remoteVersion;

  /// 上次同步时间
  final DateTime? lastSyncAt;

  /// 冲突明细
  final List<SyncConflictView> conflicts;

  /// 失败原因（phase=error 时）
  final String? error;

  /// 已知设备数
  final int deviceCount;

  /// 是否已配置
  final bool configured;

  /// 开关是否开启
  final bool enabled;

  /// 构造
  const SyncStatusView({
    required this.phase,
    this.remoteLabel,
    this.localVersion,
    this.remoteVersion,
    this.lastSyncAt,
    this.conflicts = const <SyncConflictView>[],
    this.error,
    this.deviceCount = 0,
    this.configured = false,
    this.enabled = false,
  });

  /// 未配置占位
  const SyncStatusView.unconfigured()
      : phase = SyncPhase.unconfigured,
        remoteLabel = null,
        localVersion = null,
        remoteVersion = null,
        lastSyncAt = null,
        conflicts = const <SyncConflictView>[],
        error = null,
        deviceCount = 0,
        configured = false,
        enabled = false;
}

/// 一份历史版本
class SyncVersionView {
  /// 版本号
  final int version;

  /// 推送设备名（未知为空串）
  final String deviceName;

  /// 推送时间
  final DateTime? at;

  /// 触发方式（manual / auto / unknown）
  final String trigger;

  /// 是否当前版本
  final bool current;

  /// 构造
  const SyncVersionView({
    required this.version,
    this.deviceName = '',
    this.at,
    this.trigger = 'unknown',
    this.current = false,
  });
}

/// 动作结果
class SyncActionResult {
  /// 是否成功
  final bool ok;

  /// 失败原因
  final String? error;

  /// 测试连接时可写标志
  final bool? writable;

  /// 构造
  const SyncActionResult({required this.ok, this.error, this.writable});

  /// 成功
  const SyncActionResult.ok({this.writable}) : ok = true, error = null;

  /// 失败
  const SyncActionResult.fail(String message)
      : ok = false,
        error = message,
        writable = null;
}

/// 云同步能力
abstract interface class SyncService {
  /// 读取当前状态
  Future<SyncStatusView> loadStatus();

  /// 测试连接（只验证，不保存）
  Future<SyncActionResult> testConnection({
    required String baseUrl,
    required String username,
    required String password,
  });

  /// 保存凭据并开启同步
  Future<SyncActionResult> saveAndEnable({
    required String baseUrl,
    required String username,
    required String password,
  });

  /// 开关
  Future<SyncActionResult> setEnabled(bool enabled);

  /// 立即同步（手动）
  Future<SyncActionResult> syncNow();

  /// 历史版本
  Future<List<SyncVersionView>> loadVersions();

  /// 回滚到指定版本
  Future<SyncActionResult> restoreVersion(int version);

  /// 重置同步（清云端与本地同步状态）
  Future<SyncActionResult> reset();
}
