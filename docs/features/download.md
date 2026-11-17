# 下载功能实现计划 —— A「已下载」

> 状态：**设计计划（未实现）** ｜ 更新：2026-11-17 ｜ 范围：重做 DownloadManager（A）；播放缓存（B）本轮不动。

## 1. 背景

下载功能按「未完成」重做。当前 A 链路存在入口拿不到地址、任务不持久化、文件落临时目录、删除不清 `local_path`、清理误删成品等硬缺陷（证据见 §2）。

## 2. 现状问题（证据摘要）

| 问题 | 证据 |
|---|---|
| 点下载不解析地址，`song.playUrl` 为空即 failed，仍弹「已开始」 | `sheets.dart:1289` → `providers.dart:3056` → `download_manager_impl.dart:59-69`；`sheets.dart:1292` |
| 文件落系统临时目录 | `download_manager_impl.dart:98` |
| 任务纯内存，重启即丢 | `download_manager_impl.dart:23`；schema 无下载表 |
| `updateSong` 是 UPDATE，未播放过下载后不落库 | `download_manager_impl.dart:157` + `sqflite_song_dao.dart:52-61` |
| 删除缓存不清 `local_path` → 幽灵已下载 | `download_manager_impl.dart:194-208`；`Song.copyWith` 无法置空 |
| 「清理已结束」误删 completed 成品 | `providers.dart:3071-3080` |
| 无并发/判重、无超时、无请求头、半截文件顶最终名 | `download_manager_impl.dart:71-79,114-124,99-100,132` |

## 3. 目标与边界

### 目标
- 入口经 `SourceManager.getPlayable` 解析地址（带 referer/UA），成功才提示；
- 文件持久化到 `getApplicationSupportDirectory()/downloads/`；
- 任务持久化（`download_tasks` 表），重启可见/可重试；
- 删除缓存同步清 `local_path`，列表/徽章/计数统一判定；
- 单并发队列 + 同曲判重 + 超时/有限重试；
- 去掉顶层「清理已结束」，改逐行操作。

### 非目标
- 播放缓存（B）本轮不改（见 §11）；
- 多线程分片下载。

## 4. 设计

### 4.1 存储与命名
- 根目录：`getApplicationSupportDirectory()/downloads/`（持久，系统不轻易清）。
- 文件：`<sourceId>/<base64url(globalKey)>.<ext>`；扩展名取自 URL/Content-Type，缺省 `.mp3`。
- 下载中写 `.part`，完成后原子 rename；半截文件绝不进入「已下载」。

### 4.2 状态机与队列
- `pending → downloading → completed | failed | cancelled`；`failed/cancelled --retry--> pending`。
- 队列：`maxConcurrent = 1`，FIFO（`queue_order`）；同 `songKey` 在排队/下载中则忽略重复请求。
- 启动恢复：加载表；`downloading` 一律改 `failed(error='上次下载中断')`，保留 `.part` 供重试续传，不自动联网。

### 4.3 地址解析与请求头
- `DownloadActions.download(song)`：先 `getPlayable`（带 `playHeadersFor(sourceId)`），再 `manager.download(song, url:, headers:)`。
- db 层不依赖 SourceManager；地址为空 → 如实失败并提示，不假报成功。

### 4.4 已下载判定
- 统一口径：`local_path` 非空 **且** 文件 `exists`。
- 列表/徽章/计数共用同一 provider；文件丢失时自动降级为未下载并回源。

### 4.5 清理与记录（去掉「清理已结束」）
- `cancel`：取消令牌 + 删 `.part` + 标 cancelled。
- `deleteCache`：删文件（含 `.part`）+ 清 `local_path` + 删任务行。
- failed/cancelled：行内「移除记录」（只删 DB 行，不动文件）；completed：行内「删除缓存」。

### 4.6 启动恢复
- 启动时 `init()`：建目录、加载 `download_tasks`、把 `downloading` 改 failed；广播一次快照。

## 5. 数据模型（DDL）

```sql
-- 新增表：加入 kCreateAllTables，靠 onOpen 幂等建表；
-- 不 bump kDbVersion（避免升级走 _dropAllTables 清掉 songs.local_path）
CREATE TABLE IF NOT EXISTS download_tasks (
  song_key       TEXT PRIMARY KEY,
  status         TEXT NOT NULL,
  progress       REAL NOT NULL DEFAULT 0,
  url            TEXT,
  local_path     TEXT,
  error          TEXT,
  total_bytes    INTEGER,
  received_bytes INTEGER,
  queue_order    INTEGER NOT NULL DEFAULT 0,
  created_at     INTEGER NOT NULL,
  updated_at     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_download_status ON download_tasks(status, queue_order);
```

> `_dropAllTables` 补 `download_tasks`（供将来真要 bump 版本时使用）。

## 6. 契约变更（core）

```dart
Future<void> download(Song song, {String? url, Map<String,String>? headers});
Future<void> cancel(String songKey);
Future<void> deleteCache(String songKey);
Future<int>  clearFailedOrCancelled(); // 行内移除记录用
Future<bool> isDownloaded(String songKey);
Stream<List<DownloadTask>> get taskStream;
List<DownloadTask> getTasks();
```

- `DownloadTask` 增 `totalBytes / receivedBytes / createdAt`；`copyWith` 支持显式置空。
- `SongDao` 增 `upsertSong(Song)`、`clearLocalPath(id, sourceId)`；`Song` 增 `withoutLocalPath()`。

## 7. 文件改动清单

- **core**：`services/download_manager.dart`、`models/song.dart`、`db/database_provider.dart`。
- **db**：`database_helper.dart`、新增 `download_task_dao.dart`、重写 `download_manager_impl.dart`、`sqflite_song_dao.dart`、`in_memory_dao.dart`。
- **uiv2**：`providers.dart`（DownloadActions/判定）、`pages/downloads_page.dart`、`components/sheets.dart`、`library_page.dart`、`components/rows.dart`。
- **docs**：本文、`01-data-schema`、`docs/README`、`features/offline-cache`（交叉说明）。

## 8. 分阶段（每阶段独立提交，先测试）

- **P0 复现测试**：deleteCache 清 localPath、未 insert 直接下载可查、clearFinished 不删成品、重启加载任务。
- **P1 数据层**：SongDao upsert/clear + Song.withoutLocalPath + download_tasks 表/DAO + 重启加载。
- **P2 下载实现**：support 目录、`.part`+原子 rename、headers、单并发队列、超时/重试、Range/If-Range。
- **P3 入口**：DownloadActions 先 getPlayable；toast 如实。
- **P4 UI**：下载页接持久化任务/进度/逐行操作；统一已下载判定。
- **P5 边界 + 文档 + 验收**：移除「仅 Wi-Fi 下载」、命名、文档、release_check 用例。

## 9. 测试计划

- db：重启恢复、未播放歌曲 upsert、delete 清 localPath、clearFailedOrCancelled 保留成品、cancel 删 `.part`、队列串行、headers、Range/If-Range。
- uiv2：下载页 widget（状态/进度/取消/重试/删除/移除记录）、入口解析（mock SourceManager）、已下载判定。
- 端到端：未播放过的歌点下载 → 完成 → 断网可播；删除后列表消失且回源。

## 10. 验收标准

1. 未播放过的歌（含需 Referer 的源）点下载能完成，`songs.local_path` 落库；
2. 重启后下载页仍显示 completed，可管理/可播放；
3. 删除缓存 → 文件、`local_path`、列表项同时消失，重播回源；
4. failed/cancelled 可「移除记录」，completed 文件不受影响；
5. 同曲连点不并发；取消后 `.part` 清理、可重试；
6. 无 Content-Length 时进度显示不确定态，不卡死。

## 11. B 侧小修（本轮不做，另立）

- `AudioCache.isCached/localUrlFor` 只信内存索引、不校验文件存在 → 外部删除后播 `file://` 失败且不回源；
- `clear()` 不取消在飞下载 → 清空后又被写回、占用不为 0；
- `audioCacheEnabled` 读取竞态（默认 true、load 不 await）→ 重启后首次播放可能误缓存；
- `init()` 被调用两次（main + binding）→ 重复扫盘/广播。

## 12. 决策记录（2026-11-17）

- 下载按「未完成」重做（A）；B 另立。
- 去掉「清理已结束」按钮；改逐行操作（completed 删除缓存；failed/cancelled 重试/移除记录）。
- 下载目录 `support/downloads`；单并发；启动中断任务标 failed 可重试。
- 移除「仅 Wi-Fi 下载」开关。
- 新表用 onOpen 幂等建表，不 bump DB 版本。
