/// 变更 → 防抖 → 同步
///
/// 把 `packages/db` 的写变更总线接到 [SyncEngine]：
///   * 收到任一实体变更后重置计时器，避免每写一次就打一次 WebDAV；
///   * 30s（可配）内静默才真正同步；
///   * 手动同步走 [flush]，立即执行并取消防抖。
library;

import 'dart:async';

import 'package:core/core.dart';

import 'sync_report.dart';

/// 防抖调度器
class SyncScheduler {
  /// 数据变更流（来自 DbChangeSource；null 表示不做自动触发）
  final Stream<DbChange>? changes;

  /// 真正执行同步的回调
  final Future<SyncReport> Function() onSync;

  /// 防抖时长（默认 30s）
  final Duration debounce;

  Timer? _timer;
  StreamSubscription<DbChange>? _sub;
  bool _disposed = false;

  /// 构造
  SyncScheduler({
    required this.changes,
    required this.onSync,
    this.debounce = const Duration(seconds: 30),
  });

  /// 开始监听（幂等）
  void start() {
    if (_disposed || changes == null) return;
    _sub ??= changes!.listen((_) => schedule());
  }

  /// 安排一次防抖同步（多次调用只保留最后一次）
  void schedule() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _timer = null;
      onSync();
    });
  }

  /// 立即同步（手动「立即同步」/ 启动拉取用），并取消待执行的防抖
  Future<SyncReport> flush() async {
    _timer?.cancel();
    _timer = null;
    return onSync();
  }

  /// 停止监听并释放资源
  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await _sub?.cancel();
    _sub = null;
  }
}
