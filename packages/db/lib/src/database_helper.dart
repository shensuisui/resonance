/// SQLite 数据库初始化与建表
///
/// 负责跨平台初始化 sqflite（移动端用默认工厂，
/// 桌面端 Windows/macOS/Linux 用 FFI），创建数据库文件，
/// 执行建表 SQL 和版本迁移。

import 'dart:convert';
import 'package:core/core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'sqflite_init.dart';

/// 数据库版本
const int kDbVersion = 1;

/// 建表 SQL
const String kCreateSongsTable = '''
CREATE TABLE IF NOT EXISTS songs (
  id          TEXT NOT NULL,
  source_id   TEXT NOT NULL,
  title       TEXT NOT NULL,
  artist      TEXT NOT NULL,
  album       TEXT,
  cover_url   TEXT,
  duration    INTEGER,
  play_url    TEXT,
  lyric_url   TEXT,
  lyric       TEXT,
  local_path  TEXT,
  extra       TEXT,
  updated_at  INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (id, source_id)
)
''';

const String kCreatePlaylistsTable = '''
CREATE TABLE IF NOT EXISTS playlists (
  id                  TEXT PRIMARY KEY,
  name                TEXT NOT NULL,
  source_id           TEXT,
  source_playlist_id  TEXT,
  cover_url           TEXT,
  created_time        INTEGER NOT NULL,
  modified_time       INTEGER NOT NULL
)
''';

const String kCreatePlaylistSongsTable = '''
CREATE TABLE IF NOT EXISTS playlist_songs (
  playlist_id  TEXT NOT NULL,
  song_key     TEXT NOT NULL,
  position     INTEGER NOT NULL,
  PRIMARY KEY (playlist_id, song_key),
  FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
)
''';

const String kCreateRecentPlaysTable = '''
CREATE TABLE IF NOT EXISTS recent_plays (
  song_key   TEXT PRIMARY KEY,
  played_at  INTEGER NOT NULL
)
''';

const String kCreateRecentPlaysIndex = '''
CREATE INDEX IF NOT EXISTS idx_recent_played_at ON recent_plays(played_at DESC)
''';

const String kCreateFavoritesTable = '''
CREATE TABLE IF NOT EXISTS favorites (
  song_key       TEXT PRIMARY KEY,
  favorite_time  INTEGER NOT NULL
)
''';

/// 设置表（key-value，支持多设备同步预留）
const String kCreateSettingsTable = '''
CREATE TABLE IF NOT EXISTS settings (
  key         TEXT PRIMARY KEY,
  value       TEXT,
  updated_at  INTEGER NOT NULL
)
''';

/// 所有建表 SQL（按顺序执行）
const List<String> kCreateAllTables = [
  kCreateSongsTable,
  kCreatePlaylistsTable,
  kCreatePlaylistSongsTable,
  kCreateRecentPlaysTable,
  kCreateRecentPlaysIndex,
  kCreateFavoritesTable,
  kCreateSettingsTable,
];

/// 数据库助手
///
/// 负责：
/// 1. 跨平台初始化（移动端 sqflite 默认 / 桌面端 FFI）
/// 2. 在应用文档目录创建/打开数据库文件
/// 3. 执行建表与版本迁移
class DatabaseHelper {
  Database? _database;

  /// 自定义数据库路径（测试用）
  /// 为 null 时使用 [getApplicationDocumentsDirectory] 默认路径
  final String? customDbPath;

  DatabaseHelper({this.customDbPath});

  /// 获取数据库实例（单例，懒加载）
  Future<Database> getDatabase() async {
    if (_database != null) return _database!;

    // 跨平台初始化（移动端 sqflite / 桌面端 FFI / Web FFI-Web）
    initSqfliteForPlatform();

    // 获取数据库文件路径
    final dbPath = customDbPath ?? await _getDefaultPath();

    // 打开/创建数据库
    _database = await openDatabase(
      dbPath,
      version: kDbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    return _database!;
  }

  /// 默认数据库路径
  Future<String> _getDefaultPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'fm_music.db');
  }

  /// 首次创建数据库时执行建表
  Future<void> _onCreate(Database db, int version) async {
    for (final sql in kCreateAllTables) {
      await db.execute(sql);
    }
  }

  /// 版本升级时执行迁移
  ///
  /// 当前只有 v1，未来新增版本在此分支处理。
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v1 → v2, v2 → v3, ... 在此添加
  }

  /// 关闭数据库（用于测试和清理）
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}

// ==================== Song ↔ Map 映射 ====================

/// Song 转 DB 行 Map
///
/// [updated_at] 由 DB 层自动填充，不映射自 Song 模型。
Map<String, Object?> songToMap(Song song) {
  return {
    'id': song.id,
    'source_id': song.sourceId,
    'title': song.title,
    'artist': song.artist,
    'album': song.album,
    'cover_url': song.coverUrl,
    'duration': song.duration,
    'play_url': song.playUrl,
    'lyric_url': song.lyricUrl,
    'lyric': song.lyric,
    'local_path': song.localPath,
    'extra': song.extra.isNotEmpty ? jsonEncode(song.extra) : null,
    'updated_at': DateTime.now().millisecondsSinceEpoch,
  };
}

/// DB 行 Map 转 Song
Song songFromMap(Map<String, Object?> row) {
  return Song(
    id: row['id'] as String,
    sourceId: row['source_id'] as String,
    title: row['title'] as String,
    artist: row['artist'] as String,
    album: row['album'] as String?,
    coverUrl: row['cover_url'] as String?,
    duration: row['duration'] as int?,
    playUrl: row['play_url'] as String?,
    lyricUrl: row['lyric_url'] as String?,
    lyric: row['lyric'] as String?,
    localPath: row['local_path'] as String?,
    extra: row['extra'] != null
        ? jsonDecode(row['extra'] as String) as Map<String, dynamic>
        : const {},
  );
}
