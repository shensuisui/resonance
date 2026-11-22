/// 一次同步的结果（供 UI 展示）
library;

import 'package:portable/portable.dart';

/// 一次同步的结果
class SyncReport {
  /// 应用到的记录数（合并结果规模）
  final int pulled;

  /// 是否推送了新版本
  final bool pushed;

  /// 同步前的远端版本（无远端为 null）
  final int? fromVersion;

  /// 同步后的版本（未推送时等于 fromVersion）
  final int? toVersion;

  /// 冲突数（双方都改过且 data 不同）
  final int conflicts;

  /// 冲突明细（供「冲突详情」展示）
  final List<MergeConflict> conflictList;

  /// 是否成功
  final bool success;

  /// 失败原因（成功时为 null）
  final String? error;

  /// 结束时间
  final DateTime at;

  /// 构造
  const SyncReport({
    this.pulled = 0,
    this.pushed = false,
    this.fromVersion,
    this.toVersion,
    this.conflicts = 0,
    this.conflictList = const <MergeConflict>[],
    this.success = true,
    this.error,
    required this.at,
  });

  /// 失败结果
  factory SyncReport.failure(String error, {DateTime? at}) => SyncReport(
        success: false,
        error: error,
        at: at ?? DateTime.now(),
      );

  @override
  String toString() {
    final err = error == null ? '' : ', error: $error';
    return 'SyncReport(success: $success, v$fromVersion→$toVersion, '
        'pushed: $pushed, pulled: $pulled, conflicts: $conflicts$err)';
  }
}

/// 同步流程错误（并发冲突 / 快照缺失或校验失败等）
class SyncException implements Exception {
  /// 面向用户的说明
  final String message;

  /// 构造
  const SyncException(this.message);

  @override
  String toString() => message;
}
