/// db 包 — SQLite 持久化层
///
/// 提供全平台（Android/iOS/Windows/macOS/Linux）的 SQLite 数据库实现。
/// 通过依赖注入将 SqfliteDatabaseProvider 传入 core 的 SourceManager 等组件。

library db;

export 'src/database_helper.dart';
export 'src/sqflite_song_dao.dart';
export 'src/sqflite_playlist_dao.dart';
export 'src/sqflite_recent_plays_dao.dart';
export 'src/sqflite_favorites_dao.dart';
export 'src/sqflite_settings_dao.dart';
export 'src/sqflite_database_provider.dart';
export 'src/download_manager_impl.dart';
