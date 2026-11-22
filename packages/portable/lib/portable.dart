/// 可移植数据层：记录模型 + DB 读写 + 合并（云同步 / 导入导出共用）
library;

export 'src/local_snapshot_applier.dart';
export 'src/local_snapshot_reader.dart';
export 'src/merge.dart';
export 'src/settings_keys.dart';
export 'src/snapshot.dart';
export 'src/backup_model.dart';
export 'src/backup_codec.dart';
export 'src/backup_archive.dart';
export 'src/backup_service.dart';
