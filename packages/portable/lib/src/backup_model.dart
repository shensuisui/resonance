/// 备份文档（v2，记录式）+ 分区/模式/报告
library;

import 'snapshot.dart';

/// 设备本地设置分区名（不在 SyncEntity 里，仅备份可选）
const String kDeviceSettingsEntity = 'device_settings';

/// 可勾选的数据分区
enum BackupSection { songs, playlists, favorites, recent, settings, progress, deviceSettings }

/// 分区 → 实体名
String entityOf(BackupSection section) => switch (section) {
      BackupSection.songs => SyncEntity.songs,
      BackupSection.playlists => SyncEntity.playlists,
      BackupSection.favorites => SyncEntity.favorites,
      BackupSection.recent => SyncEntity.recent,
      BackupSection.settings => SyncEntity.settings,
      BackupSection.progress => SyncEntity.progress,
      BackupSection.deviceSettings => kDeviceSettingsEntity,
    };

/// 导入模式
enum BackupImportMode { merge, overwrite }

/// 单分区结果
class ImportSectionReport {
  final int added;
  final int skipped;
  final int updated;
  const ImportSectionReport({this.added = 0, this.skipped = 0, this.updated = 0});
  ImportSectionReport plus({int added = 0, int skipped = 0, int updated = 0}) =>
      ImportSectionReport(
        added: this.added + added,
        skipped: this.skipped + skipped,
        updated: this.updated + updated,
      );
  @override
  String toString() => 'added=$added, skipped=$skipped, updated=$updated';
}

/// 导入总报告
class ImportReport {
  final Map<BackupSection, ImportSectionReport> sections;
  final List<String> warnings;
  const ImportReport({required this.sections, this.warnings = const <String>[]});
  ImportSectionReport of(BackupSection section) =>
      sections[section] ?? const ImportSectionReport();
  int get totalAdded => sections.values.fold<int>(0, (a, b) => a + b.added);
  int get totalSkipped => sections.values.fold<int>(0, (a, b) => a + b.skipped);
  int get totalUpdated => sections.values.fold<int>(0, (a, b) => a + b.updated);
}

/// 备份文档（记录式）
class BackupDocument {
  final int version;
  final DateTime exportedAt;
  final String deviceId;
  final Map<String, List<SyncRecord>> entities;
  final List<AssetEntry> assets;
  const BackupDocument({
    this.version = 2,
    required this.exportedAt,
    this.deviceId = 'unknown',
    this.entities = const <String, List<SyncRecord>>{},
    this.assets = const <AssetEntry>[],
  });
  Map<String, int> get stats {
    final playlistSongs = (entities[SyncEntity.playlists] ?? const <SyncRecord>[])
        .fold<int>(0, (sum, r) => sum + ((r.data['songKeys'] as List?)?.length ?? 0));
    final songRecords = entities[SyncEntity.songs]?.length ?? 0;
    return <String, int>{
        'songs': songRecords > playlistSongs ? songRecords : playlistSongs,
        'playlists': entities[SyncEntity.playlists]?.length ?? 0,
        'favorites': entities[SyncEntity.favorites]?.length ?? 0,
        'recent': entities[SyncEntity.recent]?.length ?? 0,
        'progress': entities[SyncEntity.progress]?.length ?? 0,
        'settings': entities[SyncEntity.settings]?.length ?? 0,
        'deviceSettings': entities[kDeviceSettingsEntity]?.length ?? 0,
        'assets': assets.length,
      };
  }
}

/// 备份结构/版本错误
class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => message;
}
