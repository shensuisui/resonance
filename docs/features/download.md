# 下载功能实现计划 —— A「已下载」

> 状态：**设计计划（未实现）** ｜ 更新：2026-11-17 ｜ 范围：重做 DownloadManager（A）；播放缓存（B）本轮不动。
> 目标形态：**外部可用成品**（可读文件名 + 基础标签 + 封面缩略图 + 歌词）。

## 1. 背景

下载按「未完成」重做。当前 A 链路存在：入口不解析地址、任务不持久化、文件落临时目录、删除不清 local_path、清理误删成品等（证据见 §2）。

## 2. 现状问题（证据摘要）

| 问题 | 证据 |
|---|---|
| 点下载不解析地址，playUrl 为空即 failed，仍弹「已开始」 | `sheets.dart:1289` → `providers.dart:3056` → `download_manager_impl.dart:59-69`；`sheets.dart:1292` |
| 文件落系统临时目录 | `download_manager_impl.dart:98` |
| 任务纯内存，重启即丢 | `download_manager_impl.dart:23`；schema 无下载表 |
| `updateSong` 是 UPDATE，未播放过下载后不落库 | `download_manager_impl.dart:157` + `sqflite_song_dao.dart:52-61` |
| 删除缓存不清 local_path → 幽灵已下载 | `download_manager_impl.dart:194-208`；`Song.copyWith` 无法置空 |
| 顶层「清理已结束」误删 completed 成品 | `providers.dart:3071-3080` |
| 无并发/判重、无超时/请求头、半截文件顶最终名 | `download_manager_impl.dart:71-79,114-124,99-100,132` |

## 3. 目标与边界

### 目标
- 下载文件为**外部可用成品**：可读文件名 + 基础标签 + 封面缩略图 + 歌词；
- 入口经 `SourceManager.getPlayable`（带 referer/UA）解析地址，成功才提示；
- 持久化到 `getApplicationSupportDirectory()/downloads/`；任务持久化（`download_tasks` 表）；
- 缓存命中优先**拷贝**（magic 校验通过才拷贝，拷后删缓存）；
- 删除缓存同步清 local_path；统一「已下载」判定；单并发队列 + 同曲判重；
- 去掉顶层「清理已结束」，改逐行操作。

### 非目标
- 播放缓存（B）本轮不改（见 §11）；多线程分片下载。

## 4. 设计

### 4.1 目录与命名
- 根目录：`getApplicationSupportDirectory()/downloads/<sourceId>/`。
- 文件名：`<歌手> - <歌曲>.<ext>`（默认）或 `<歌曲> - <歌手>.<ext>`，由设置项 `download_name_order` 切换。
- 清洗：非法字符（`\\ / : * ? " < > |` 与控制字符）替换为 `_`；去首尾空格；最长 120 字符；未知歌手=「未知歌手」，空标题回退 song.id。
- 冲突：同名追加 ` (2)`、` (3)`…
- 扩展名：优先按 Content-Type / URL 推断；推断不出时读文件头 magic（ID3/MPEG→mp3、fLaC→flac、ftyp→m4a、OggS→ogg）；仍未知回落 `.mp3`。

### 4.2 状态机与队列
- `pending → downloading → completed | failed | cancelled`；`failed/cancelled --retry--> pending`。
- `maxConcurrent = 1`，FIFO；同 songKey 在排队/下载中则忽略重复请求。
- 启动恢复：加载表；`downloading` 改 `failed(error='上次下载中断')`，保留 `.part` 供重试，不自动联网。

### 4.3 地址解析与请求头
- `DownloadActions.download(song)`：先 `getPlayable` + `playHeadersFor(sourceId)`，再 `manager.download(song, url:, headers:, lyrics:)`。
- db 层不依赖 SourceManager；地址为空 → 如实失败，不假报成功。

### 4.4 缓存命中 → 拷贝
- 条件：`AudioCache` 有该曲完整缓存（无 `.part`、非空），且**文件头 magic 校验通过**（不设大小阈值）。
- 动作：拷贝到下载目录（走同一命名/清洗/冲突规则）→ 删除该曲缓存副本。
- 拷贝后同样执行元信息写入。

### 4.5 元信息写入（外部可用）
- 基础标签：title / artist / album / duration。
- 封面：取 `coverUrl`（带 headers）→ 压成 **256×256 JPEG 质量 85** 缩略图 → 写入 pictures。
- 歌词：若 `songs.lyric` 为空，先 `ensureLyrics`；**原样嵌入 LRC（含时间戳）**。
- 失败策略：**下载仍算成功**，写 `warning`（无歌词 / 封面失败 / 格式不支持 / 标签写入失败）。
- 支持格式：mp3 / m4a / flac / ogg（audiotags）；其它格式跳过标签并记 warning。

### 4.6 已下载判定
- 统一：`local_path` 非空 **且** 文件 `exists`。列表/徽章/计数共用同一 provider；文件丢失自动降级未下载并回源。

### 4.7 清理与记录（去掉「清理已结束」）
- `cancel`：取消令牌 + 删 `.part` + cancelled。
- `deleteCache`：删文件（含 `.part`）+ 清 `local_path` + 删任务行。
- completed：行内「删除缓存」；failed/cancelled：行内「重试」/「移除记录」（只删行）。

### 4.8 启动恢复
- `init()`：建目录、加载 `download_tasks`、`downloading`→failed；广播快照。

### 4.9 设置项（P4 需先出预览图）
- `download_name_order`：artist_title（默认）/ title_artist；
- `download_cover_size`：256（默认）/ 512 / 1024；
- `download_cover_quality`：默认 85。
> 设置页属于视觉改动，按约定 **先出忠实预览图（真实令牌/组件/字体）供审核**，再写实现。

## 5. 数据模型（DDL）

```sql
CREATE TABLE IF NOT EXISTS download_tasks (
  song_key       TEXT PRIMARY KEY,
  status         TEXT NOT NULL,
  progress       REAL NOT NULL DEFAULT 0,
  url            TEXT,
  local_path     TEXT,
  error          TEXT,
  warning        TEXT,
  total_bytes    INTEGER,
  received_bytes INTEGER,
  queue_order    INTEGER NOT NULL DEFAULT 0,
  created_at     INTEGER NOT NULL,
  updated_at     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_download_status ON download_tasks(status, queue_order);
```
> 仅加表：加入 kCreateAllTables、靠 onOpen 幂等建表，**不 bump kDbVersion**；`_dropAllTables` 补 `download_tasks`。

## 6. 契约变更（core）

```dart
Future<void> download(Song song, {String? url, Map<String,String>? headers, String? lyrics});
Future<void> cancel(String songKey);
Future<void> deleteCache(String songKey);
Future<int>  removeRecord(String songKey); // 仅删 failed/cancelled 记录
Future<bool> isDownloaded(String songKey);
Stream<List<DownloadTask>> get taskStream;
List<DownloadTask> getTasks();
```

- `DownloadTask` 增 `totalBytes / receivedBytes / warning / createdAt`；`copyWith` 支持显式置空。
- `SongDao` 增 `upsertSong`、`clearLocalPath`；`Song` 增 `withoutLocalPath()`。

## 7. 文件改动清单

- **core**：`services/download_manager.dart`、`models/song.dart`、`db/database_provider.dart`。
- **db**：`database_helper.dart`、新增 `download_task_dao.dart`、重写 `download_manager_impl.dart`（含 magic/拷贝/标签）、`sqflite_song_dao.dart`、`in_memory_dao.dart`。
- **uiv2**：`providers.dart`（DownloadActions/解析/判定）、`pages/downloads_page.dart`、`components/sheets.dart`、`library_page.dart`、`components/rows.dart`、`settings_page.dart`（新增设置项，先预览）。
- **docs**：本文、`01-data-schema`、`docs/README`、`features/offline-cache`。

## 8. 分阶段（每阶段独立提交，先测试）

- **P0 复现测试**：deleteCache 清 localPath、未 insert 直接下载可查、removeRecord 不删文件、重启加载任务、「无地址即失败且不假报」。
- **P1 数据层**：SongDao upsert/clear、Song.withoutLocalPath、download_tasks 表/DAO、重启加载。
- **P2 下载实现**：support 目录、命名/清洗/冲突、magic 扩展名、`.part`+原子 rename、headers、单并发、超时/重试、Range/If-Range、缓存拷贝（magic 校验 + 拷后删缓存）。
- **P3 元信息**：audiotags 写基础标签；封面缩略图（256 JPEG85）；ensureLyrics + LRC；失败 warning。
- **P4 入口/UI**：DownloadActions 先解析地址；toast 如实；下载页逐行操作；统一已下载判定；设置项（先出预览图）。
- **P5 边界/文档/验收**：移除「仅 Wi-Fi 下载」、外部删除自愈、文档、release_check 用例。

## 9. 测试计划

- db：重启恢复、未播放 upsert、delete 清 localPath、removeRecord 保留文件、cancel 删 `.part`、队列串行、headers、Range/If-Range、magic 判断、缓存拷贝+删缓存。
- tags：mp3/m4a 写入基础标签/封面/歌词；不支持格式 warning；歌词缺失 warning。
- uiv2：下载页 widget（状态/进度/取消/重试/删除/移除记录）、入口解析（mock SourceManager）、已下载判定。
- 端到端：未播放过的歌（需 Referer 源）点下载 → 完成 → 断网可播 → 外部播放器可识别标签。

## 10. 验收标准

1. 未播放过的歌（含需 Referer 的源）点下载能完成，`songs.local_path` 落库；
2. 重启后下载页仍显示 completed，可管理/可播放；
3. 文件名为「歌手 - 歌曲」且可配置；标签含标题/歌手/专辑/时长/封面/歌词；
4. 缓存命中时拷贝而非重下（magic 校验），拷后缓存被删；
5. 删除缓存 → 文件、local_path、列表项同时消失；重播回源；
6. failed/cancelled 可移除记录，completed 文件不受影响；同曲不并发；取消清 `.part`；
7. 无 Content-Length 时进度不确定态，不卡死。

## 11. B 侧小修（本轮不做，另立）

- `isCached/localUrlFor` 不校验文件存在；`clear()` 不取消在飞；`audioCacheEnabled` 读取竞态；`init()` 调用两次。

## 12. 决策记录（2026-11-17）

- 目标：外部可用成品（可读名 + 基础标签 + 封面缩略图 + 歌词）。
- 命名：顺序可配置（默认「歌手 - 歌曲」）；目录按 `sourceId`；冲突 ` (2)`；非法字符 `_`、最长 120。
- 扩展名：Content-Type/URL 优先，缓存拷贝读 magic；未知回落 mp3。
- 缓存命中：magic 校验通过才拷贝，拷后删缓存副本。
- 元信息：基础 + 封面（256 JPEG85）+ 歌词（LRC 原样；缺失 warning）；写标签失败仅 warning。
- 设置项：命名顺序 / 封面尺寸 / 封面质量（P4 先出预览图）。
- 去掉「清理已结束」；逐行操作。
- 外部删除：检测不存在 → 标未下载并清 local_path。
- 移除「仅 Wi-Fi 下载」。
- 新表 onOpen 建表，不 bump DB 版本。
