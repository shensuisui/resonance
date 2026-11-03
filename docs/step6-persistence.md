# Step 6: 持久化层

| 步骤 | 6 |
| :--- | :--- |
| 包 | `core` |
| 依赖 | Step 1（数据模型） |
| 状态 | 待实现 |

---

## 1. 概述

`core` 包的持久化层，使用 SQLite（`sqflite` 或 `drift`）存储本地数据。包括数据库初始化、表结构定义、DAO 实现。

> 由于 `core` 是纯 Dart 包，SQLite 实现使用 `sqflite_common_ffi`（桌面端）或设计为 `DatabaseProvider` 抽象，由上层注入具体实现。**推荐方案**：在 `core` 中定义 DAO 接口和 SQL 语句（纯 Dart），由 `ui` 或 `resonance_app` 提供数据库实例。

## 2. 表结构

### 2.1 songs

| 字段 | 类型 | 约束 |
| :--- | :--- | :--- |
| id | TEXT | NOT NULL |
| source_id | TEXT | NOT NULL |
| title | TEXT | NOT NULL |
| artist | TEXT | NOT NULL |
| album | TEXT | |
| cover_url | TEXT | |
| duration | INTEGER | |
| play_url | TEXT | |
| lyric_url | TEXT | |
| lyric | TEXT | |
| local_path | TEXT | |
| extra | TEXT | JSON 字符串 |
| PRIMARY KEY | | (id, source_id) |

### 2.2 playlists

| 字段 | 类型 | 约束 |
| :--- | :--- | :--- |
| id | TEXT | PRIMARY KEY (UUID) |
| name | TEXT | NOT NULL |
| song_keys | TEXT | NOT NULL, JSON 数组 |
| source_id | TEXT | |
| source_playlist_id | TEXT | |
| cover_url | TEXT | |
| created_time | INTEGER | |
| modified_time | INTEGER | |

### 2.3 recent_plays

| 字段 | 类型 | 约束 |
| :--- | :--- | :--- |
| song_key | TEXT | PRIMARY KEY |
| played_at | INTEGER | NOT NULL, Unix 毫秒 |

### 2.4 favorites

| 字段 | 类型 | 约束 |
| :--- | :--- | :--- |
| song_key | TEXT | PRIMARY KEY |
| favorite_time | INTEGER | NOT NULL, Unix 毫秒 |

## 3. DAO 接口

```dart
abstract class SongDao {
  Future<void> insertSong(Song song);
  Future<Song?> getSong(String id, String sourceId);
  Future<List<Song>> searchSongs(String keyword);
  Future<void> updateSong(Song song);
  Future<void> deleteSong(String id, String sourceId);
}

abstract class PlaylistDao {
  Future<void> insertPlaylist(Playlist playlist);
  Future<Playlist?> getPlaylist(String id);
  Future<List<Playlist>> getAllPlaylists();
  Future<void> updatePlaylist(Playlist playlist);
  Future<void> deletePlaylist(String id);
}

abstract class RecentPlaysDao {
  Future<void> insertOrUpdateRecentPlay(String songKey, int playedAt);
  Future<List<String>> getRecentPlayKeys({int limit = 500});
  Future<void> cleanOldest(int maxCount);
}

abstract class FavoritesDao {
  Future<void> addFavorite(String songKey, int time);
  Future<void> removeFavorite(String songKey);
  Future<bool> isFavorite(String songKey);
  Future<List<String>> getAllFavoriteKeys();
}
```

## 4. DatabaseProvider 抽象

```dart
abstract class DatabaseProvider {
  Future<void> initialize();
  // 各 DAO 的获取方法
  SongDao get songDao;
  PlaylistDao get playlistDao;
  RecentPlaysDao get recentPlaysDao;
  FavoritesDao get favoritesDao;
}
```

- `core` 包提供 DAO 接口和默认实现
- `ui` 或 `resonance_app` 注入具体的 `DatabaseProvider`（如基于 `sqflite` 的实现）

## 5. 包结构变更

```
packages/core/lib/src/db/
├── database_provider.dart    # DatabaseProvider 抽象
├── song_dao.dart             # SongDao 接口 + 默认实现
├── playlist_dao.dart         # PlaylistDao 接口 + 默认实现
├── recent_dao.dart           # RecentPlaysDao 接口 + 默认实现
└── favorites_dao.dart        # FavoritesDao 接口 + 默认实现
```

## 6. 测试用例

- 各 DAO 的 CRUD 正确性
- 最近播放列表的上限清理逻辑
- 收藏的添加/移除/查询
- 歌曲搜索匹配