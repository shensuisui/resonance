# 数据库 Schema（现行）

> 以 packages/db/lib/src/database_helper.dart 为准（schema 版本仍为 **v4**；下载任务表通过 onOpen 幂等补建，不 bump 版本）。SQLite 实现在 packages/db。

## 1. 平台与 Provider
- Android / iOS：sqflite；Windows / macOS / Linux：sqflite_common_ffi；Web：FFI-Web（sqflite_init_web）。
- core 定义 DatabaseProvider + **7 个 DAO 接口**（含 DownloadTaskDao）；db 实现 SqfliteDatabaseProvider。版本 kDbVersion=4，升级策略为「删旧表重建 + onOpen 幂等补表」。

## 2. 表结构（8 张）
~~~sql
songs(id, source_id, title, artist, album, cover_url, duration, play_url,
      lyric_url, lyric, local_path, extra, updated_at, PK(id,source_id))

playlists(id PK, name, source_id, source_playlist_id, cover_url,
          created_time, modified_time)

playlist_songs(playlist_id, song_key, position,
               title, artist, cover_url, duration,
               PK(playlist_id,song_key), FK→playlists ON DELETE CASCADE)

recent_plays(song_key PK, played_at, title, artist, cover_url)
  + idx_recent_played_at(played_at DESC)

favorites(song_key PK, favorite_time, title, artist, cover_url)

settings(key PK, value, updated_at)

play_progress(queue_kind, queue_id DEFAULT '', song_key, position_ms, updated_at,
              PK(queue_kind, queue_id))

download_tasks(song_key PK, status, progress, url, local_path, error, warning,
               total_bytes, received_bytes, queue_order, created_at, updated_at)
  + idx_download_status(status, queue_order)
~~~

## 3. 约束与策略
- Song 唯一键为 (id, source_id)；跨源引用用 song_key = 「sourceId:id」。
- 快照列（v2~v4 渐进引入）：recent_plays / favorites 存 title/artist/cover_url；playlist_songs 存 title/artist/cover_url/duration，供列表直接渲染、免回源。
- playlist_songs 以 position 保序；删除歌单时 CASCADE 删关联。
- recent_plays 上限 500（超出清最旧）；insert 去重、移顶。
- play_progress 一个队列一行（queue_kind ∈ recent/playlist/liked/local），只存「听到哪」，曲目每次从真实数据重建。
- settings 键值对：theme_mode / play_mode / search_history / source_enabled_<id> / audio_cache_play 等（与 v1 ui 包键名互通）；下载设置键：download_name_order / download_cover_size / download_cover_quality（2026-11-18 已实现）。
- download_tasks：status ∈ pending/downloading/completed/failed/cancelled；启动时 downloading→failed（保留 .part 供重试）；completed 行与 songs.local_path 对应，local_path 清空即视为未下载。

## 4. DAO（7 类）
SongDao、PlaylistDao（含关联表）、RecentPlaysDao、FavoritesDao、SettingsDao、PlayProgressDao、DownloadTaskDao；DatabaseProvider 组装 7 者。另 DownloadManager / AudioCache 为实现（非表）。

## 5. 代码侧备注
- **字段命名**：AudioMetadata 的 `durationMs` 与 LocalScanSource 的 `durationMs` 实为**秒**（audiotags Rust `as_secs()`），与 Song.duration（秒）一致，**无单位 bug**；名称易误解，可在后续重命名。
- （历史）曾记 `_dropAllTables` 缺 `play_progress` —— **已修复**（2026-11-13 补入 drop 列表）。
