/// 自动同步运行器：变更防抖 + 启动/回前台拉取 + 前台定时 + 仅 Wi-Fi
///
/// 依赖抽象 [AutoSyncHost]（ShellSyncService 实现），便于单测：
///   * 数据变更（db 变更总线）→ 防抖 → 自动同步；
///   * 启动/回前台 → 立即拉取（若开启）；
///   * 定时：仅前台 Timer（不引入 workmanager）；
///   * 仅 Wi-Fi：非 Wi-Fi 时跳过自动同步（手动同步不受限）。
library;

import 'dart:async';

import 'package:core/core.dart';

/// 自动同步宿主
abstract interface class AutoSyncHost {
  /// 数据写变更流（可为 null）
  Stream<DbChange>? get changes;

  /// 配置变化（开关/时机变更时触发重新排程）
  Stream<void> get configChanges;

  /// 是否启用
  Future<bool> get enabled;

  /// 是否仅 Wi-Fi
  Future<bool> get wifiOnly;

  /// 启动/回前台是否拉取
  Future<bool> get startupPull;

  /// 变更防抖（毫秒）
  Future<int> get debounceMillis;

  /// 定时同步间隔（毫秒；0=关）
  Future<int> get intervalMillis;

  /// 执行一次自动同步
  Future<void> syncAuto();
}

/// 自动同步运行器
class SyncAutoRunner {
  final AutoSyncHost host;

  /// 网络判断（null = 不判断，视为允许）
  final Future<bool> Function()? isOnWifi;

  Timer? _debounce;
  Timer? _interval;
  StreamSubscription<DbChange>? _changeSub;
  StreamSubscription<void>? _configSub;
  bool _busy = false;
  bool _started = false;

  /// 构造
  SyncAutoRunner({required this.host, this.isOnWifi});

  /// 启动（幂等）：订阅变更与配置，并立即按配置排程（含启动拉取）
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _changeSub = host.changes?.listen((_) => _onChange());
    _configSub = host.configChanges.listen((_) => _reload());
    await _reload();
  }

  /// 回前台：若开启启动拉取则补一次
  Future<void> onForeground() async {
    if (!await host.enabled) return;
    if (await host.startupPull) await _run();
  }

  Future<void> _reload() async {
    _interval?.cancel();
    _interval = null;
    if (!await host.enabled) return;
    if (await host.startupPull) unawaited(_run());
    final ms = await host.intervalMillis;
    if (ms > 0) {
      _interval = Timer.periodic(Duration(milliseconds: ms), (_) => _run());
    }
  }

  Future<void> _onChange() async {
    if (!await host.enabled) return;
    final ms = await host.debounceMillis;
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: ms), _run);
  }

  Future<void> _run() async {
    if (_busy) return;
    if (await host.wifiOnly) {
      final ok = isOnWifi == null ? true : await isOnWifi!();
      if (!ok) return;
    }
    _busy = true;
    try {
      await host.syncAuto();
    } on Object {
      // 自动同步失败不打扰用户；状态由下一次状态刷新体现
    } finally {
      _busy = false;
    }
  }

  /// 仅测试/退出用：取消所有计时器与订阅
  Future<void> dispose() async {
    _debounce?.cancel();
    _interval?.cancel();
    await _changeSub?.cancel();
    await _configSub?.cancel();
    _debounce = null;
    _interval = null;
    _changeSub = null;
    _configSub = null;
    _started = false;
  }
}
