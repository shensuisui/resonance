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

/// 单个实体的合并结果
class MergeOutcome {
  /// 合并后的记录
  final List<SyncRecord> records;

  /// 冲突数（双方都改过且 data 不同）
  final int conflicts;

  /// 构造
  const MergeOutcome({required this.records, required this.conflicts});
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
    var conflicts = 0;

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
        if (localChanged && remoteChanged) conflicts++;
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
