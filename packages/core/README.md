# core — resonance 核心模块

纯 Dart 包（无 Flutter 依赖），承载全应用的领域模型与统一抽象。

## 职责
- 数据模型：Song / Album / Artist / Lyrics / Playlist / SearchResult / PlayerState / SourceInfo 等。
- 统一接口：MusicSource（音乐源）、Player（播放器抽象）、各 DAO、DownloadManager。
- SourceManager：源注册 / 启停 / 并行聚合搜索 / 按源路由。
- 本地源：LocalScanSource、LocalCustomSource、FavoriteSource；业务服务 RecentPlaysService。
- 持久化只定义 DAO 接口，SQLite 实现见 packages/db。

## 依赖
无第三方运行时依赖（纯 Dart）。

## 测试
在 packages/core 下运行 dart test（本机 Flutter SDK 见仓库 .fvm/flutter_sdk）。
