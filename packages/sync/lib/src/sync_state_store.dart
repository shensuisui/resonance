/// 同步状态存储：上次基线快照 + 已知远端版本
///
/// 刻意做成接口：真实实现写 App 私有目录（壳工程注入），
/// 单测用内存实现；引擎不直接依赖文件系统。
library;

import 'snapshot.dart';

/// 同步状态存储
abstract interface class SyncStateStore {
  /// 读上次成功同步的基线（无则 null）
  Future<SyncSnapshot?> readBaseline();

  /// 写基线（null = 清空）
  Future<void> writeBaseline(SyncSnapshot? baseline);

  /// 读已知远端版本（无则 null）
  Future<int?> readKnownVersion();

  /// 写已知远端版本（null = 清空）
  Future<void> writeKnownVersion(int? version);
}

/// 内存实现（单测 / 临时会话用）
class MemorySyncStateStore implements SyncStateStore {
  SyncSnapshot? _baseline;
  int? _version;

  @override
  Future<SyncSnapshot?> readBaseline() async => _baseline;

  @override
  Future<void> writeBaseline(SyncSnapshot? baseline) async {
    _baseline = baseline;
  }

  @override
  Future<int?> readKnownVersion() async => _version;

  @override
  Future<void> writeKnownVersion(int? version) async {
    _version = version;
  }
}
