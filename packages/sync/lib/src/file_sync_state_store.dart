/// 文件版同步状态存储：基线快照 + 已知远端版本
///
/// 落盘位置由壳工程注入（App 私有目录，如 applicationSupportDirectory/sync），
/// 引擎不直接依赖 path_provider：
///   * baseline.tar.bz2 —— 上次成功同步的基线（复用快照编解码，带资产清单）
///   * state.json        —— {"knownVersion": N}
///
/// 容错：基线损坏/读失败按「没有基线」处理（下次同步视为新设备，不做删除推断），
/// 宁可不传播删除，也不能拿坏数据把云端删掉。
library;

import 'dart:convert';
import 'dart:io';

import 'snapshot.dart';
import 'snapshot_codec.dart';
import 'sync_state_store.dart';

/// 文件实现
class FileSyncStateStore implements SyncStateStore {
  /// 目录（不存在会自动创建）
  final String dir;

  /// 构造
  const FileSyncStateStore(this.dir);

  String get _baselinePath => '$dir/baseline.tar.bz2';

  String get _statePath => '$dir/state.json';

  Future<Directory> _ensureDir() async {
    final d = Directory(dir);
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  @override
  Future<SyncSnapshot?> readBaseline() async {
    try {
      final file = File(_baselinePath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return SnapshotCodec.decode(bytes).snapshot;
    } on Exception {
      // 损坏/不可读：当作没有基线（安全侧：不推断删除）
      return null;
    }
  }

  @override
  Future<void> writeBaseline(SyncSnapshot? baseline) async {
    await _ensureDir();
    final file = File(_baselinePath);
    if (baseline == null) {
      if (await file.exists()) await file.delete();
      return;
    }
    final bytes = SnapshotCodec.encode(SnapshotBundle(snapshot: baseline));
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<int?> readKnownVersion() async {
    try {
      final file = File(_statePath);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return null;
      final v = json['knownVersion'];
      return v is num ? v.toInt() : null;
    } on Exception {
      return null;
    }
  }

  @override
  Future<void> writeKnownVersion(int? version) async {
    await _ensureDir();
    final file = File(_statePath);
    await file.writeAsString(
      jsonEncode(<String, Object?>{'knownVersion': version}),
      flush: true,
    );
  }
}
