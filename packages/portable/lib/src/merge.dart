/// 合并纯函数（无 IO、无平台依赖，可单测）
///
/// 规则见 docs/features/webdav-sync.md §7：
///   * 每条记录按 (updatedAt, deviceId) 取「更新者」；
///   * 先应用墓碑：deletedAt > updatedAt 的记录删除（记录更新过 = 重新加入）；
///   * 歌单按 **id** 合并（B2）：曲目取并集，顺序以较新者为主序列、另一份的独有曲目追加末尾；
///     同名但 id 不同视为两张不同歌单（不静默合并）；
///   * 冲突计数：双方都改过（相对基线）且 data 不同。
library;

import 'dart:convert';

import 'snapshot.dart';

/// 一条冲突（双方都改过且 data 不同）
class MergeConflict {
  /// 实体分区
  final String entity;

  /// 记录 key
  final String key;

  /// 本机侧的 updatedAt
  final int localUpdatedAt;

  /// 远端侧的 updatedAt
  final int remoteUpdatedAt;

  /// 构造
  const MergeConflict({
    required this.entity,
    required this.key,
    required this.localUpdatedAt,
    required this.remoteUpdatedAt,
  });

  @override
  String toString() =>
      'MergeConflict($entity/$key, local: $localUpdatedAt, remote: $remoteUpdatedAt)';
}

/// 单个实体的合并结果
class MergeOutcome {
  /// 合并后的记录
  final List<SyncRecord> records;

  /// 具体冲突项
  final List<MergeConflict> conflicts;

  /// 构造
  const MergeOutcome({required this.records, this.conflicts = const <MergeConflict>[]});

  /// 冲突数
  int get conflictCount => conflicts.length;
}

/// 合并器
abstract final class Merger {
  /// 合并单个实体
  ///
  /// [baseline] 为「上次同步基线」：用于判断「某侧是否改过」，
  /// 从而把冲突计数限定在「双方都改过且不同」；为空时退化为
  /// 「双方都有且 data 不同即冲突」。
  static MergeOutcome mergeEntity({
    required String entity,
    required List<SyncRecord> local,
    required List<SyncRecord> remote,
    List<Tombstone> tombstones = const <Tombstone>[],
    List<SyncRecord>? baseline,
  }) {
    final localByKey = <String, SyncRecord>{for (final r in local) r.key: r};
    final remoteByKey = <String, SyncRecord>{for (final r in remote) r.key: r};
    final baseByKey = <String, SyncRecord>{
      for (final r in (baseline ?? const <SyncRecord>[])) r.key: r,
    };
    final dead = _tombstonesOf(entity, tombstones);

    final keys = <String>{...localByKey.keys, ...remoteByKey.keys};
    final merged = <SyncRecord>[];
    final conflicts = <MergeConflict>[];

    for (final key in keys) {
      final l = localByKey[key];
      final r = remoteByKey[key];
      final tomb = dead[key];

      // 1) 先应用墓碑：删除时间晚于记录时间 → 记录已死
      final newer = _newer(l, r);
      if (newer == null) continue;
      if (tomb != null && tomb.deletedAt > newer.updatedAt) continue;

      // 2) 冲突计数（在合并前判断，歌单的「顺序合并」不算冲突）
      if (entity != SyncEntity.playlists &&
          l != null &&
          r != null &&
          !_sameData(l.data, r.data)) {
        final base = baseByKey[key];
        final localChanged = _changed(l, base);
        final remoteChanged = _changed(r, base);
        if (localChanged && remoteChanged) {
          conflicts.add(MergeConflict(
            entity: entity,
            key: key,
            localUpdatedAt: l.updatedAt,
            remoteUpdatedAt: r.updatedAt,
          ));
        }
      }

      // 3) 歌单：曲目并集 + 顺序以较新者为主
      if (entity == SyncEntity.playlists && l != null && r != null) {
        merged.add(_mergePlaylist(l, r));
      } else {
        merged.add(newer);
      }
    }

    // 稳定排序，便于测试与 diff（按 key 字典序）
    merged.sort((a, b) => a.key.compareTo(b.key));
    return MergeOutcome(records: merged, conflicts: conflicts);
  }

  /// 无基线合并：逐 key 取 updatedAt 较新者（同刻比 deviceId），保留并集
  ///
  /// 用于「备份导入」这类没有基线、只需“新覆盖旧”的场景；不产生冲突。
  static List<SyncRecord> mergeNewer(
    List<SyncRecord> local,
    List<SyncRecord> incoming,
  ) {
    final localByKey = <String, SyncRecord>{for (final r in local) r.key: r};
    final incomingByKey = <String, SyncRecord>{
      for (final r in incoming) r.key: r,
    };
    final keys = <String>{...localByKey.keys, ...incomingByKey.keys};
    final out = <SyncRecord>[];
    for (final key in keys) {
      final l = localByKey[key];
      final r = incomingByKey[key];
      if (l == null) {
        out.add(r!);
      } else if (r == null) {
        out.add(l);
      } else if (r.updatedAt > l.updatedAt) {
        out.add(r);
      } else {
        // 时间相同：保留本机（备份导入不做无意义覆盖）
        out.add(l);
      }
    }
    out.sort((a, b) => a.key.compareTo(b.key));
    return out;
  }
  /// 合并资产清单（按 mtime 判胜；仅墓碑才删）
  ///
  /// 资产没有逐记录的 deviceId：mtime 相同则比 sha256（大者胜），保证确定。
  /// 删除只认墓碑（决策 35：远端有、本地无不视为删除）。
  static List<AssetEntry> mergeAssets({
    required List<AssetEntry> local,
    required List<AssetEntry> remote,
    List<Tombstone> tombstones = const <Tombstone>[],
  }) {
    final localBy = <String, AssetEntry>{for (final a in local) a.path: a};
    final remoteBy = <String, AssetEntry>{for (final a in remote) a.path: a};
    final dead = _tombstonesOf(SyncEntity.assets, tombstones);
    final paths = <String>{...localBy.keys, ...remoteBy.keys};
    final out = <AssetEntry>[];

    for (final path in paths) {
      final l = localBy[path];
      final r = remoteBy[path];
      AssetEntry? winner;
      if (l == null) {
        winner = r;
      } else if (r == null) {
        winner = l;
      } else if (l.mtime != r.mtime) {
        winner = l.mtime > r.mtime ? l : r;
      } else {
        winner = l.sha256.compareTo(r.sha256) >= 0 ? l : r;
      }
      if (winner == null) continue;
      final tomb = dead[path];
      if (tomb != null && tomb.deletedAt > winner.mtime) continue;
      out.add(winner);
    }
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }

  /// 取墓碑：同 key 取 deletedAt 最大者
  static Map<String, Tombstone> _tombstonesOf(
    String entity,
    List<Tombstone> tombstones,
  ) {
    final map = <String, Tombstone>{};
    for (final t in tombstones) {
      if (t.entity != entity) continue;
      final prev = map[t.key];
      if (prev == null || t.deletedAt > prev.deletedAt) map[t.key] = t;
    }
    return map;
  }

  /// 两条记录取「更新者」：先比 updatedAt，相等再比 deviceId（大者胜）
  static SyncRecord? _newer(SyncRecord? a, SyncRecord? b) {
    if (a == null) return b;
    if (b == null) return a;
    if (a.updatedAt != b.updatedAt) {
      return a.updatedAt > b.updatedAt ? a : b;
    }
    return a.deviceId.compareTo(b.deviceId) >= 0 ? a : b;
  }

  /// 相对基线是否改过
  static bool _changed(SyncRecord current, SyncRecord? base) {
    if (base == null) return true;
    return current.updatedAt != base.updatedAt ||
        !_sameData(current.data, base.data);
  }

  /// 合并两张同名歌单：曲目并集、顺序以较新者为主、快照以较新者优先
  static SyncRecord _mergePlaylist(SyncRecord a, SyncRecord b) {
    final winner = _newer(a, b)!;
    final loser = identical(winner, a) ? b : a;
    final data = Map<String, Object?>.from(winner.data);

    final winnerKeys =
        ((winner.data['songKeys'] as List?) ?? const <Object?>[]).cast<String>();
    final loserKeys =
        ((loser.data['songKeys'] as List?) ?? const <Object?>[]).cast<String>();
    final keys = <String>[...winnerKeys];
    for (final k in loserKeys) {
      if (!keys.contains(k)) keys.add(k);
    }
    data['songKeys'] = keys;

    final winnerSnaps =
        ((winner.data['snapshots'] as Map?) ?? const <String, Object?>{})
            .cast<String, Object?>();
    final loserSnaps =
        ((loser.data['snapshots'] as Map?) ?? const <String, Object?>{})
            .cast<String, Object?>();
    data['snapshots'] = <String, Object?>{
      ...loserSnaps,
      ...winnerSnaps, // 较新者优先
    };

    return winner.copyWith(
      updatedAt: winner.updatedAt > loser.updatedAt
          ? winner.updatedAt
          : loser.updatedAt,
      data: data,
    );
  }

  /// data 深比较（key 排序后序列化，避免 Map 顺序影响）
  static bool _sameData(Map<String, Object?> a, Map<String, Object?> b) =>
      _canonical(a) == _canonical(b);

  /// 规范化：递归排序 Map 的键
  static String _canonical(Object? value) => jsonEncode(_normalize(value));

  /// 递归规范化（Map 键排序，便于稳定比较）
  static Object? _normalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => '$k').toList()..sort();
      return <String, Object?>{
        for (final k in keys) k: _normalize(value[k]),
      };
    }
    if (value is List) {
      return <Object?>[for (final v in value) _normalize(v)];
    }
    return value;
  }
}
