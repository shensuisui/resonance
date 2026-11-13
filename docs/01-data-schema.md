# 数据库 Schema（现行）

> 从 [s1-sqlite-persistence](implementation/s1-sqlite-persistence.md) 与 [summary-s1-s3](summaries/summary-s1-s3.md) 的 S1 提炼。SQLite 实现位于 packages/db。
> 状态：现行 ｜ 更新：2026-11-13

## 1. 平台与 Provider
- Android / iOS：sqflite；Windows / macOS / Linux：sqflite_common_ffi（sqfliteFfiInit + databaseFactoryFfi）；Web 暂不支持。
- core 只定义 DAO 接口；db 包实现 SqfliteDatabaseProvider 并组装各 DAO；壳工程注入。

## 2. 表结构
~~~sql
-- 歌曲表（复合主键）
CREATE TABLE songs (
  id TEXT NOT NULL, source_id TEXT NOT NULL,
  title TEXT NOT NULL, artist TEXT NOT NULL, album TEXT,
  cover_url TEXT, duration INTEGER, play_url TEXT, lyric_url TEXT, lyric TEXT,
  local_path TEXT, extra TEXT,
  PRIMARY KEY (id, source_id)
);
-- 歌单表
CREATE TABLE playlists (
  id TEXT PRIMARY KEY, name TEXT NOT NULL,
  source_id TEXT, source_playlist_id TEXT, cover_url TEXT,
  created_time INTEGER NOT NULL, modified_time INTEGER NOT NULL
);
-- 歌单-歌曲（保序）
CREATE TABLE playlist_songs (
  playlist_id TEXT NOT NULL, song_key TEXT NOT NULL, position INTEGER NOT NULL,
  PRIMARY KEY (playlist_id, song_key),
  FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
);
-- 最近播放
CREATE TABLE recent_plays (
  song_key TEXT PRIMARY KEY, played_at INTEGER NOT NULL
);
CREATE INDEX idx_recent_played_at ON recent_plays(played_at DESC);
-- 收藏
CREATE TABLE favorites (
  song_key TEXT PRIMARY KEY, favorite_time INTEGER NOT NULL
);
-- 设置（键值对）
CREATE TABLE settings (
  key TEXT PRIMARY KEY, value TEXT
);
~~~

## 3. 约束与策略
- Song 唯一键为 (id, source_id)；跨源引用用 song_key = 「sourceId:id」。
- playlist_songs 以 position 保序；删除歌单时 CASCADE 删关联。
- recent_plays 上限 500（超出清最旧）；insert 即去重、移顶。
- settings 存键值对：theme_mode、play_mode、search_history、source_enabled_<id>、audio_cache_play 等（与 v1 ui 包键名互通）。

## 4. DAO 清单
SongDao、PlaylistDao（含关联表）、RecentPlaysDao、FavoritesDao、SettingsDao；另有 DatabaseProvider（组装）与 DownloadManager（下载缓存）。
