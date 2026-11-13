# db — SQLite 持久化层

实现 core 的 DAO 接口与 DownloadManager。

## 职责
- 跨平台 SQLite：Android / iOS 用 sqflite；Windows / macOS / Linux 用 sqflite_common_ffi。
- DAO：SongDao / PlaylistDao / RecentPlaysDao / FavoritesDao / SettingsDao。
- DownloadManager 实现（dio 下载 + path_provider 缓存）。
- audiotags 读取本地音频标签。

## 依赖
core、sqflite、sqflite_common_ffi、audiotags、path_provider、dio。

## 测试
在 packages/db 下运行 flutter test。
