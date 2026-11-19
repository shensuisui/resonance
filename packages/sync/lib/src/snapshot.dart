/// 同步快照的数据模型（纯 Dart，不含 IO）
///
/// 与 docs/features/webdav-sync.md §6 对应：
///   * 一个快照 = snapshot.json（全部实体记录 + 墓碑）+ assets/ 文件树；
///   * 记录级字段：key / updatedAt(ms) / deviceId / data。
library;

/// 快照内的一条记录
class SyncRecord {
  /// 合并键（收藏/最近=song_key；进度=kind|id；设置=key；歌曲=source:id；歌单=name）
  final String key;

  /// 该记录最后变更时间（毫秒，UTC）
  final int updatedAt;

  /// 最后写入设备
  final String deviceId;

  /// 实体内核字段
  final Map<String, Object?> data;

  /// 构造
  const SyncRecord({
    required this.key,
    required this.updatedAt,
    required this.deviceId,
    required this.data,
  });

  /// 转 JSON
  Map<String, Object?> toJson() => <String, Object?>{
        'key': key,
        'updatedAt': updatedAt,
        'deviceId': deviceId,
        'data': data,
      };

  /// 从 JSON 还原
  factory SyncRecord.fromJson(Map<String, Object?> json) => SyncRecord(
        key: json['key'] as String,
        updatedAt: (json['updatedAt'] as num).toInt(),
        deviceId: json['deviceId'] as String? ?? '',
        data: (json['data'] as Map).cast<String, Object?>(),
      );

  SyncRecord copyWith({int? updatedAt, String? deviceId, Map<String, Object?>? data}) =>
      SyncRecord(
        key: key,
        updatedAt: updatedAt ?? this.updatedAt,
        deviceId: deviceId ?? this.deviceId,
        data: data ?? this.data,
      );

  @override
  String toString() => 'SyncRecord($key, $updatedAt)';
}

/// 删除墓碑：某实体某 key 在 [deletedAt] 被删除
class Tombstone {
  /// 实体分区名（[SyncEntity] 之一，或 assets）
  final String entity;

  /// 被删记录的键（assets 时为相对路径）
  final String key;

  /// 删除时间（毫秒，UTC）
  final int deletedAt;

  /// 执行删除的设备
  final String deviceId;

  /// 构造
  const Tombstone({
    required this.entity,
    required this.key,
    required this.deletedAt,
    required this.deviceId,
  });

  /// 转 JSON
  Map<String, Object?> toJson() => <String, Object?>{
        'entity': entity,
        'key': key,
        'deletedAt': deletedAt,
        'deviceId': deviceId,
      };

  /// 从 JSON 还原
  factory Tombstone.fromJson(Map<String, Object?> json) => Tombstone(
        entity: json['entity'] as String,
        key: json['key'] as String,
        deletedAt: (json['deletedAt'] as num).toInt(),
        deviceId: json['deviceId'] as String? ?? '',
      );

  @override
  String toString() => 'Tombstone($entity/$key @$deletedAt)';
}

/// 快照内的实体分区名
abstract final class SyncEntity {
  /// 歌曲索引
  static const String songs = 'songs';

  /// 歌单
  static const String playlists = 'playlists';

  /// 收藏
  static const String favorites = 'favorites';

  /// 最近播放
  static const String recent = 'recent';

  /// 播放进度
  static const String progress = 'progress';

  /// 设置
  static const String settings = 'settings';

  /// 资产文件（在 zip 的 assets/ 下，不进 entities）
  static const String assets = 'assets';

  /// 所有实体分区
  static const List<String> all = <String>[
    songs,
    playlists,
    favorites,
    recent,
    progress,
    settings,
  ];
}

/// 一份完整快照（不含资产字节）
class SyncSnapshot {
  /// 快照版本号（与 latest.json 的 version 一致）
  final int version;

  /// 生成时间（毫秒，UTC）
  final int updatedAt;

  /// 生成设备
  final String writer;

  /// 实体分区 → 记录
  final Map<String, List<SyncRecord>> entities;

  /// 删除墓碑
  final List<Tombstone> tombstones;

  /// 构造
  const SyncSnapshot({
    required this.version,
    required this.updatedAt,
    required this.writer,
    this.entities = const <String, List<SyncRecord>>{},
    this.tombstones = const <Tombstone>[],
  });

  /// 记录总数（统计/UI 用）
  int get recordCount =>
      entities.values.fold<int>(0, (sum, list) => sum + list.length);

  /// 取某分区（不存在返回空）
  List<SyncRecord> recordsOf(String entity) =>
      entities[entity] ?? const <SyncRecord>[];

  /// 复制并覆盖字段（引擎构造新快照时用）
  SyncSnapshot copyWith({
    int? version,
    int? updatedAt,
    String? writer,
    Map<String, List<SyncRecord>>? entities,
    List<Tombstone>? tombstones,
  }) =>
      SyncSnapshot(
        version: version ?? this.version,
        updatedAt: updatedAt ?? this.updatedAt,
        writer: writer ?? this.writer,
        entities: entities ?? this.entities,
        tombstones: tombstones ?? this.tombstones,
      );
}

/// 快照 + 资产文件（assets 以相对路径 → 字节表示）
class SnapshotBundle {
  /// 快照主体
  final SyncSnapshot snapshot;

  /// 资产文件：相对路径（如 subscriptions/index.json）→ 字节
  final Map<String, List<int>> assets;

  /// 构造
  const SnapshotBundle({required this.snapshot, this.assets = const {}});
}

/// 快照结构/版本不兼容
class SnapshotException implements Exception {
  /// 面向用户的说明
  final String message;

  /// 构造
  const SnapshotException(this.message);

  @override
  String toString() => message;
}
