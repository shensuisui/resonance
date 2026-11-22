/// 备份服务：导出/导入复用 LocalSnapshotReader/Applier/Merger
///
/// 语义（v2）：
///   * 导出：从 DB 读成记录（与云同步同构），资产可选；
///   * 导入 merge：逐记录按 updatedAt 判胜（新覆盖旧、旧跳过），并集写回；
///   * 导入 overwrite：先清空所选分区再写入（歌曲目录只并集、不删除）。
library;

import 'dart:convert';

import 'package:core/core.dart';
import 'package:crypto/crypto.dart';

import 'backup_archive.dart';
import 'backup_model.dart';
import 'local_snapshot_applier.dart';
import 'local_snapshot_reader.dart';
import 'merge.dart';
import 'settings_keys.dart';
import 'snapshot.dart';

/// 备份服务
class BackupService {
  /// 数据库
  final DatabaseProvider db;

  /// 资产来源（可选；导出勾选资产时使用）
  final BackupAssetSource? assetSource;

  /// 本设备 id（写入记录）
  final String deviceId;

  /// 时钟
  final DateTime Function() clock;

  /// 构造
  BackupService({
    required this.db,
    this.assetSource,
    this.deviceId = 'local',
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  /// 导出整包
  Future<BackupDocument> exportAll({
    bool includeDeviceSettings = false,
    bool includeAssets = false,
    DateTime? now,
  }) async {
    final at = now ?? clock();
    final reader = LocalSnapshotReader(db: db, deviceId: deviceId);
    final snapshot = await reader.read(version: 2, writer: deviceId, now: at);
    final entities = <String, List<SyncRecord>>{...snapshot.entities};
    if (includeDeviceSettings) {
      entities[kDeviceSettingsEntity] = await _readDeviceSettings();
    }
    var assets = const <AssetEntry>[];
    if (includeAssets && assetSource != null) {
      final files = await assetSource!.readAll();
      assets = <AssetEntry>[
        for (final f in files)
          AssetEntry(path: f.path, sha256: _sha256Hex(f.bytes), mtime: f.mtime),
      ];
    }
    return BackupDocument(
      exportedAt: at,
      deviceId: deviceId,
      entities: entities,
      assets: assets,
    );
  }

  /// 读取资产字节（导出 zip 时用）
  Future<Map<String, List<int>>> readAssetBytes() async {
    if (assetSource == null) return const <String, List<int>>{};
    final files = await assetSource!.readAll();
    return <String, List<int>>{for (final f in files) f.path: f.bytes};
  }

  /// 导入
  Future<ImportReport> importDocument(
    BackupDocument document, {
    BackupImportMode mode = BackupImportMode.merge,
    Set<BackupSection>? sections,
  }) async {
    final selected = sections ?? BackupSection.values.toSet();
    final now = clock();
    final reader = LocalSnapshotReader(db: db, deviceId: deviceId);
    final local = await reader.read(version: 2, writer: deviceId, now: now);

    // 未选分区保留本机记录，避免 applier 把它们当“远端缺失”删掉
    final applyEntities = <String, List<SyncRecord>>{
      for (final entity in SyncEntity.all)
        entity: local.entities[entity] ?? const <SyncRecord>[],
    };

    final reports = <BackupSection, ImportSectionReport>{};
    for (final section in selected) {
      final entity = entityOf(section);
      final incoming = document.entities[entity] ?? const <SyncRecord>[];
      if (entity == kDeviceSettingsEntity) {
        reports[section] = await _importDeviceSettings(incoming, mode);
        continue;
      }
      final localList = local.entities[entity] ?? const <SyncRecord>[];
      final localByKey = <String, SyncRecord>{for (final r in localList) r.key: r};
      var added = 0;
      var updated = 0;
      var skipped = 0;
      for (final record in incoming) {
        final localRecord = localByKey[record.key];
        if (localRecord == null) {
          added++;
        } else if (_newerSide(record, localRecord)) {
          updated++;
        } else {
          skipped++;
        }
      }
      reports[section] = ImportSectionReport(
        added: added,
        skipped: skipped,
        updated: updated,
      );

      if (entity == SyncEntity.songs) {
        // 歌曲目录只并集，绝不删除（删了会连带本地播放/文件关联）
        applyEntities[entity] = Merger.mergeNewer(localList, incoming);
      } else if (mode == BackupImportMode.overwrite) {
        if (entity == SyncEntity.playlists) {
          for (final p in await db.playlistDao.getAllPlaylists()) {
            await db.playlistDao.deletePlaylist(p.id);
          }
        }
        applyEntities[entity] = incoming;
      } else {
        applyEntities[entity] = Merger.mergeNewer(localList, incoming);
      }
    }

    final snapshot = SyncSnapshot(
      version: 2,
      updatedAt: now.millisecondsSinceEpoch,
      writer: deviceId,
      entities: applyEntities,
    );
    await LocalSnapshotApplier(db: db).apply(snapshot);
    return ImportReport(sections: reports);
  }

  Future<List<SyncRecord>> _readDeviceSettings() async {
    final entries = await db.settingsDao.getAllEntries();
    return <SyncRecord>[
      for (final entry in entries)
        if (PortableSettingsKeys.deviceLocalKeys.contains(entry.key))
          SyncRecord(
            key: entry.key,
            updatedAt: entry.updatedAt,
            deviceId: deviceId,
            data: <String, Object?>{'key': entry.key, 'value': entry.value},
          ),
    ];
  }

  Future<ImportSectionReport> _importDeviceSettings(
    List<SyncRecord> incoming,
    BackupImportMode mode,
  ) async {
    final entries = await db.settingsDao.getAllEntries();
    final localByKey = <String, SettingEntry>{
      for (final e in entries)
        if (PortableSettingsKeys.deviceLocalKeys.contains(e.key)) e.key: e,
    };
    var added = 0;
    var updated = 0;
    var skipped = 0;
    if (mode == BackupImportMode.overwrite) {
      for (final key in localByKey.keys) {
        await db.settingsDao.delete(key);
      }
    }
    for (final record in incoming) {
      final value = (record.data['value'] as String?) ?? '';
      final localRecord = localByKey[record.key];
      if (localRecord == null) {
        await db.settingsDao.set(record.key, value);
        added++;
      } else if (record.updatedAt > localRecord.updatedAt) {
        await db.settingsDao.set(record.key, value);
        updated++;
      } else {
        skipped++;
      }
    }
    return ImportSectionReport(added: added, skipped: skipped, updated: updated);
  }

  /// incoming 是否比 local 新（同刻比 deviceId，保证确定性）
  bool _newerSide(SyncRecord incoming, SyncRecord local) =>
      incoming.updatedAt > local.updatedAt;

  static String _sha256Hex(List<int> bytes) =>
      sha256.convert(bytes).toString();
}
