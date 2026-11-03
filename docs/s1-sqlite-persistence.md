# S1：SQLite 持久化层

| 状态 | 进行中 |
|:---|:---|
| 涉及包 | core（接口）, db（新包，SQLite 实现）, resonance_app（注入） |

---

## 1. 设计决策

### 1.1 为什么新建 `packages/db` 包

`core` 是纯 Dart 包（无 Flutter 依赖），不能引入 `sqflite`（Flutter 插件）或 `path_provider`（Flutter 插件）。SQLite 实现需要 Flutter 运行时，因此放在独立的 Flutter package `db` 中。

- `core`：保持纯 Dart，定义 DAO 接口 + 业务服务接口
- `db`：Flutter package，实现 SQLite DAO + DownloadManager

### 1.2 跨平台 SQLite 方案

| 平台 | 方案 | 库 |
|:---|:---|:---|
| Android / iOS | sqflite 默认 | `sqflite` |
| Windows / macOS / Linux | FFI | `sqflite_common_ffi` |
| Web | 暂不支持 | — |

初始化逻辑：`Platform.isWindows \|\| Platform.isLinux \|\| Platform.isMacOS` → `sqfliteFfiInit()` + `databaseFactory = databaseFactoryFfi`。

### 1.3 依赖关系

```
db → core + sqflite + sqflite_common_ffi + path_provider + dio
```

---

## 2. SQLite Schema

```sql
-- 歌曲表（复合主键）
CREATE TABLE songs (
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
  extra       TEXT,           -- JSON 编码
  PRIMARY KEY (id, source_id)
);

-- 歌单表
CREATE TABLE playlists (
  id                  TEXT PRIMARY KEY,
  name                TEXT NOT NULL,
  source_id           TEXT,
  source_playlist_id  TEXT,
  cover_url           TEXT,
  created_time        INTEGER NOT NULL,
  modified_time       INTEGER NOT NULL
);

-- 歌单-歌曲关联表（保序）
CREATE TABLE playlist_songs (
  playlist_id  TEXT NOT NULL,
  song_key     TEXT NOT NULL,
  position     INTEGER NOT NULL,
  PRIMARY KEY (playlist_id, song_key),
  FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
);

-- 最近播放表
CREATE TABLE recent_plays (
  song_key   TEXT PRIMARY KEY,
  played_at  INTEGER NOT NULL
);
CREATE INDEX idx_recent_played_at ON recent_plays(played_at DESC);

-- 收藏表
CREATE TABLE favorites (
  song_key       TEXT PRIMARY KEY,
  favorite_time  INTEGER NOT NULL
);
```

---

## 3. 实现清单

### 3.1 `packages/db` 包

| 文件 | 职责 |
|:---|:---|
| `lib/src/database_helper.dart` | SQLite 初始化、建表、版本迁移 |
| `lib/src/sqflite_song_dao.dart` | SongDao 实现 |
| `lib/src/sqflite_playlist_dao.dart` | PlaylistDao 实现（含关联表操作） |
| `lib/src/sqflite_recent_plays_dao.dart` | RecentPlaysDao 实现 |
| `lib/src/sqflite_favorites_dao.dart` | FavoritesDao 实现 |
| `lib/src/sqflite_database_provider.dart` | DatabaseProvider 实现，组装四个 DAO |
| `lib/src/download_manager_impl.dart` | DownloadManager 实现（dio 下载 + path_provider 缓存） |
| `lib/db.dart` | barrel export |

### 3.2 `packages/core` 新增

| 文件 | 职责 |
|:---|:---|
| `lib/src/services/recent_plays_service.dart` | 最近播放业务逻辑（去重/移顶/500上限） |
| `lib/src/services/download_manager.dart` | DownloadManager 抽象接口 |

### 3.3 `resonance_app` 接入

`main.dart` 初始化 `SqfliteDatabaseProvider`，注入 `SourceManager` / `LocalCustomSource` / `FavoriteSource`。

---

## 4. Song ↔ Map 映射

```dart
// Song → DB row
{
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
  'extra': jsonEncode(song.extra),
}

// DB row → Song
Song(
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
  extra: row['extra'] != null ? jsonDecode(row['extra']) : {},
)
```

---

## 5. Playlist ↔ Map 映射

Playlist 的 `songKeys` 通过 `playlist_songs` 关联表存储，保持顺序：

- `insertPlaylist`：插入 playlist 行 + 批量插入 playlist_songs
- `getPlaylist`：查 playlist 行 + 查 playlist_songs 按 position 排序 → 组装 songKeys
- `updatePlaylist`：更新 playlist 行 + 删旧 playlist_songs + 插新
- `deletePlaylist`：删 playlist 行（CASCADE 自动删关联）
