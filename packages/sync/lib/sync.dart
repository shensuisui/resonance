/// sync 包 — WebDAV 云同步
///
/// 设计见 docs/features/webdav-sync.md：
///   * 云端只存「快照链 + latest 指针」，合并在各设备本机完成；
///   * 快照 = tar.bz2（snapshot.json + assets/），保留最近 7 份。
library;

export 'src/asset_store.dart';
export 'src/dav_client.dart';
export 'src/file_sync_state_store.dart';
export 'src/dav_client_webdav.dart';
export 'src/latest.dart';
export 'src/local_snapshot_applier.dart';
export 'src/local_snapshot_reader.dart';
export 'src/merge.dart';
export 'src/sync_settings_keys.dart';
export 'src/snapshot.dart';
export 'src/snapshot_codec.dart';
export 'src/sync_engine.dart';
export 'src/sync_report.dart';
export 'src/sync_scheduler.dart';
export 'src/sync_state_store.dart';
