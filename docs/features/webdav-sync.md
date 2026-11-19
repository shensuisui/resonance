# WebDAV 云同步 —— 方案调研与设计

> 状态：**设计稿**（2026-11-19 与用户逐轮拍板，只做设计、不含实现代码）。
> 关联：[data-import-export](data-import-export.md)（现有整包备份/导入，本方案在其分区模型上扩展）、[01-data-schema](../01-data-schema.md)。
> 本文档已并入「快照链」同步模型（§6/§8），实施前请看 §19「实施期验证清单」。

---

## 0. 结论速览（TL;DR）

- **传输**：WebDAV 当「哑存储会合点」——各设备把「全量压缩快照」推到同一目录，**合并全部在本机算**，云端不跑逻辑。
- **模型（①'）**：**快照链 + `latest.json` 指针，保留最近 7 份**；每个快照 = 「全部实体 + 资产文件树 + 墓碑」的压缩包，**快照内按记录合并**（不是快照级 LWW）。
- **身份**：每设备生成稳定 `deviceId`（UUID，存设置）；每条记录带 `updatedAt(ms)`，平手用 `deviceId` 兜底。
- **删除**：墓碑随快照携带（`snapshot.json.tombstones`），合并时执行删除；按年龄回收（默认 90 天），7 份历史兜底误删。
- **合并/覆盖**：**自动同步永远合并**；手动「恢复云快照 / 历史版本」才可选 合并 / 覆盖。
- **首次接入**：远端空 → 推本机；新设备 → 先拉后合；设置里可「重置同步」清云端。
- **并发**：推送前先 GET `latest.json` 版本，若已变则先拉回合并再推（乐观并发）。
- **安全**：WebDAV 账号进系统安全存储；**上传明文（JSON / tar.bz2）**（用户已接受；含订阅 URL 的风险与缓解见 §9）。
- **时机**：启动/回前台拉取 + 变更后 30s 防抖推送 + 仅 Wi-Fi；**默认全关**，用户手动开；定时可选、自定义分钟，**仅前台/启动补跑，不引入 workmanager**。
- **模块**：新建 `packages/sync`，依赖 `core + db`，注入 WebDAV 客户端；`uiv2` 只接 UI。
- **测试**：`shelf_dav` 在测试内起真实 WebDAV 服务器，跑真实 `PUT/GET/PROPFIND/MOVE`。

---

## 1. 背景与目标

### 1.1 现状（决定改造量的事实）

1. **已有整包备份/导入**：`packages/core/lib/src/services/backup_codec.dart` + `backup_service.dart` 已实现 `resonance-backup` JSON v1 的导出/导入，分区为 **歌单 / 收藏 / 最近播放 / 设置(白名单) / 播放进度**，支持 `merge`/`overwrite` 两种模式，并已处理「本地曲目回写 songs 表」「同名歌单合并」「设备本地项不入备份」。
2. **明确预留了云同步**：`docs/features/data-import-export.md` 写明「云同步 / 多设备自动同步 = PRD 预留 updated_at，本期仅单文件备份」；`database_helper.dart`、`sqflite_settings_dao.dart` 均注释「多设备同步预留」。
3. **设备本地字段不能跨设备**：`songs.local_path`、`scan_dir`、`download_tasks`、音频缓存、歌词引用——只在同机有意义。
4. **订阅源是文件存储、不在 DB**：`packages/ui/lib/src/providers/subscription_library.dart` 把订阅库写在 `applicationSupportDirectory/subscriptions/`：`index.json`（订阅 URL 列表）+ 每个订阅一个 `base64url(url)/` 目录（`manifest.json` + 展开的规则文件）。因此「订阅源相关」同步的是**这棵文件树**。
5. **时间列现状**：`songs / settings / play_progress` 有 `updated_at`；`playlists` 有 `modified_time`；`favorites.favorite_time`、`recent_plays.played_at` 本身就是该记录的变更时间；**只有 `playlist_songs` 的顺序/增删没有时间列**（见 §13）。
6. **无后台任务库**：全项目 `workmanager` 命中 0（见 §10）。

### 1.2 目标

- 多设备（Android / Windows / macOS / Linux / iOS）之间，**元数据自动/手动双向同步**：歌单、收藏、最近播放、播放进度、设置、歌曲索引、订阅源/规则资产。
- 在 WebDAV（坚果云 / Nextcloud / AList / 自建）这类**通用哑存储**上工作，不依赖特定厂商 API。
- 冲突可控、删除可传播、首次接入不出错、失败可见可重试、可回滚到近 7 次状态。
- 复用现有备份的编解码与分区模型，不重复造轮子。

### 1.3 非目标（本期不做）

- 不同步音频文件本体（不把 WebDAV 当云曲库）。
- 不做服务端（云端只存文件）。
- 不引入托管后端（Firebase/Supabase）、不引入 CRDT 引擎。
- 不做端到端加密（用户已选「明文」，见 §9）。
- 不做真后台定时（不引 workmanager）。

---

## 2. 调研：WebDAV 相关 Dart 包（实测已抓包数据）

| 包 | 最新版 / 时间 | 评分 / 赞 | 能力 | 判断 |
|---|---|---|---|---|
| [webdav_client](https://pub.dev/packages/webdav_client) | 1.2.2 / 2024-05 | 130/160 · 63👍 | dio+xml；Basic/Digest；列目录/增删改/上传下载/取消 | 生态最成熟、最常用，但 2024 后基本停更 |
| [webdav_client_plus](https://pub.dev/packages/webdav_client_plus) | 3.0.0 / 2026-10 | 160/160 · 6👍 | 上者 fork，加 crypto（digest 签名），维护活跃 | **已选**（见下） |
| [simple_webdav_client](https://pub.dev/packages/simple_webdav_client) | 0.3.0 / 2026-11 | 150/160 · 7👍 | 完整 RFC4918（含 LOCK/UNLOCK/PROPPATCH），universal_io | 最规范；备选（pre-1.0） |
| [webdav_plus](https://pub.dev/packages/webdav_plus) | 1.2.2 / 2026-01 | 110/160 · 4👍 | 锁/ACL/版本/搜索 | 功能多但人气低 |
| [nextcloud](https://pub.dev/packages/nextcloud) | 9.0.0 | 140/160 · 26👍 | 官方 Nextcloud 客户端 | 只适合 Nextcloud 专有 API，不适合通用 WebDAV |
| [webdav](https://pub.dev/packages/webdav)（timestee） | 1.0.8-dev / 2020 | — | 基础 | 停更，不用 |
| [shelf_dav](https://pub.dev/packages/shelf_dav) | 1.0.0 / 2025 | — | Dart 写的 WebDAV 服务器 | 用于本地联调 / 测试起真实服务 |

**选型结论（2026-11-19 定）**：采用 **`webdav_client_plus`**（3.0.0 / 160/160 / 活跃 / 基于最流行的 webdav_client 分支并补 digest 签名）。仍**包在自定义 `DavClient` 接口后**（§11），日后可无痛切换实现。

---

## 3. 调研：可替代的同步方案

| 方案 | 优点 | 缺点 | 结论 |
|---|---|---|---|
| **WebDAV 哑存储**（本方案） | 通用、免费/低成本、用户已有网盘；无需服务端 | 无服务端逻辑，合并/冲突全在前端；WebDAV 服务器实现参差 | ✅ 选它 |
| S3 兼容对象存储 | 一致性/成本更好 | 需密钥与桶配置，普通用户门槛高 | 备选 |
| Firebase / Supabase | 账号+实时、省事 | 绑云厂商、有费用、隐私顾虑 | 不选 |
| 自建 Dart shelf 服务 | 完全可控 | 要写服务端 + 部署运维 | 不选 |
| 外部工具（Syncthing 等） | 零服务端 | 体验割裂、用户需另装工具 | 不选 |
| 手动导出/导入（现有） | 已有、零依赖 | 非自动，需人搬文件 | 保留并存 |

---

## 4. 总体架构

```
        ┌────────── 远程 WebDAV：resonance-sync/（哑存储，不做逻辑） ──────────┐
        │   latest.json（版本指针）        snapshots/vNNNN.tar.bz2 × 最近 7 份        │
        └────────────────────────────────────────────────────────────────────────┘
             ▲ PUT 新快照 v(N+1) + latest（先 GET 版本）      │ GET latest + GET vN.tar.bz2
   ┌─────────┴────────────────┐                  ┌────────▼────────────────┐
   │ 设备A  SyncEngine          │                  │ 设备B  SyncEngine        │
   │ 下载 vN → 合并本地 → 打包 v(N+1) │              │ 下载 vN → 合并本地        │
   └───────────────────────────┘                  └──────────────────────────┘
   （合并与冲突判定全部在本机；云端只会合，不合并）
```

分层：
- **UI（uiv2）**：设置页「云同步」区块，调 `SyncController`。
- **SyncEngine（packages/sync）**：编排 下载最新快照 → 合并 → 应用 → 打包新快照上传 → 裁剪 7 份；纯逻辑可单测。
- **SnapshotCodec**：tar.bz2 读写 + `snapshot.json` 编解码 + sha256 校验。
- **DavClient（接口）**：WebDAV 读写（PROPFIND/GET/PUT/DELETE/MKCOL）。
- **Providers**：从 DAO / 文件系统读写各实体，装/卸快照。

---

## 5. 数据范围

### 5.1 参与同步（快照内实体）

| 快照内实体 | 数据来源 | 合并键 | 变更时间列 |
|---|---|---|---|
| `playlists` | `playlists` + `playlist_songs`（含顺序、快照） | 歌单 `id` | `modified_time` + §13 的 `playlist_songs.updated_at`/顺序指纹 |
| `favorites` | `favorites` | `song_key` | `favorite_time` |
| `recent` | `recent_plays`（本机上限 500 同步后截断） | `song_key` | `played_at` |
| `progress` | `play_progress` | `(queue_kind,queue_id)` | `updated_at` |
| `settings` | `settings`（云白名单，见 5.4） | `key` | `updated_at` |
| `songs` | `songs`（**剔除 `local_path`**） | `(id,source_id)` | `updated_at` |
| `assets/…`（快照包内） | 订阅库文件树 + 用户规则/插件文件 | 文件相对路径 | 文件 mtime + sha256 |

> 说明：`songs.local_path` 在打包前置空、应用时保留本机原值（不覆盖），保证「同机恢复」与「跨设备不串路径」。

### 5.2 设备本地（**不同步**）

| 项 | 原因 |
|---|---|
| `songs.local_path` | 绝对路径，跨设备无效 |
| `scan_dir`（扫描目录） | 设备本地路径 |
| `download_tasks`（下载任务/进度） | 本机下载状态 |
| 音频缓存 / 歌词缓存文件 | 可重建、体积大 |
| 同步自身的触发/凭据/状态（§10 的 `sync_*`） | 每台设备各自配置，绝不能入云 |
| 播放设备选择 `play_device` | 值是物理输出设备（本机扬声器/客厅音箱/Bose QC45），换设备无意义 |

### 5.3 订阅库与资产的精确范围（文件树）

同步对象 = 「用户可变、可重建成本高」的文件，**不含**打包进 App 的只读 `resonance_app/assets/*`（那些随 App 版本走）。

- `subscriptions/index.json`（订阅 URL 列表）
- `subscriptions/<base64url(url)>/manifest.json` + 展开的规则文件
- 用户新增/修改的规则、插件文件（若运行时落在 support 目录）

存储方式：资产文件原样放进快照包（tar）的 `assets/`（§6.3）；增删由「本地文件集 vs 快照包内文件集」差异推导，删除同样记入该快照的 `tombstones`（`entity="assets"`）。

### 5.4 云同步的设置白名单

在现有 `BackupService.exportableSettingKeys` 基础上**去掉设备本地项、补入需要的项**：

- 保留：`theme_mode, play_mode, volume, wifi_only, search_history, audio_cache_play, lyrics_open, corner_radius, seed_color, last_queue`
- 前缀：`source_enabled_`（每个源一个开关）
- 移除（设备本地）：`scan_dir`、`play_device`（物理输出设备，见 §5.2）
- 新增入云：`download_name_order`、`download_cover_size`、`download_cover_quality`（纯偏好、非路径）
- 任何 `sync_*`、`sync_device_id` 一律不进白名单

---

## 6. 云端文件结构与快照链

### 6.1 目录（快照链 + 最新指针）

```
<remoteRoot>/resonance-sync/
  latest.json                # 指针：当前版本号、对应快照文件名、sha256、writer、devices
  snapshots/
    v0042.tar.bz2                # 全量压缩快照（含全部实体 + 资产 + 墓碑）
    v0041.tar.bz2
    …                        # 只保留最近 7 份（v(N-6)..vN），更旧的自动删
```

> 与「每实体一文件 + manifest」方案相比：砍掉 `entities/`、`manifest.json`、`assets.manifest.json`、`tombstones.json` 四个概念，统一成「一条快照链 + 一个最新指针」。代价是每次全量上传/下载整包（元数据很小，见 §6.4）。

### 6.2 `latest.json`（最新指针）

```jsonc
{
  "format": "resonance-sync-latest",
  "schema": 1,
  "version": 42,
  "file": "snapshots/v0042.tar.bz2",
  "sha256": "…",                 // 快照包 .tar.bz2 的校验和
  "updatedAt": 1690000000000,
  "writer": "device-uuid-A",
  "devices": [
    { "id": "device-uuid-A", "name": "Pixel 7", "lastSeenAt": 1690000000000 }
  ]
}
```

### 6.3 快照包内部结构（`snapshots/vNNNN.tar.bz2`）

```
snapshot.json      # 清单 + 全部实体记录 + 墓碑
assets/…           # 订阅库 / 规则 / 插件文件树镜像（原样）
```

`snapshot.json`：

```jsonc
{
  "format": "resonance-sync-snapshot",
  "schema": 1,
  "version": 42,
  "updatedAt": 1690000000000,
  "writer": "device-uuid-A",
  "entities": {
    "favorites": [ { "key": "gequbao:1", "updatedAt": 1690000000000, "deviceId": "…", "data": { … } } ],
    "recent":    [ … ],
    "playlists": [ … ],
    "progress":  [ … ],
    "settings":  [ … ],
    "songs":     [ … ]
  },
  "tombstones": [
    { "entity": "favorites", "key": "gequbao:2", "deletedAt": 1690000000000, "deviceId": "device-uuid-A" },
    { "entity": "assets", "key": "subscriptions/xxx/manifest.json", "deletedAt": 1690000000000, "deviceId": "device-uuid-A" }
  ]
}
```

- 记录 `data` 为各实体内核字段；`key` 规则：收藏/最近=`song_key`；进度=`queue_kind|queue_id`；设置=`key`；歌曲=`source_id:id`；歌单=`name`；资产=相对路径。
- 资产文件按原样放进 tar 包的 `assets/`；其增删由「本地 vs 快照包内文件集」差异推导。

### 6.4 完整性与体积

- `snapshot.json` 用 JSON；整个包用 **tar 打包 + bzip2 -9 压缩**（`.tar.bz2`）。
- **实测（合成 5000 曲快照，raw JSON 2.95MB）**：`tar.bz2` = **252 KB（11.70x）**，桌面编码约 0.55s，往返字节一致。对比：`zip/deflate` 472KB(6.25x)、`zstd-3` 320KB(9.23x/154ms)、`zstd-19` 260KB(11.36x/2.46s)；`archive` 的 xz 编码器实测为 no-op（不压缩），brotli 纯 Dart 无编码器（见 §19-5）。
- 纯元数据（数千曲 ~ 几百 KB～2 MB JSON）压缩后通常几十 KB～几百 KB/份；7 份对任何 WebDAV 都可忽略。**实际以曲库实测为准**（§19-2）。
- 完整性：`latest.json.sha256` 校验快照包（`.tar.bz2`）；解压后再校验 `snapshot.json` 可解析。

### 6.5 版本保留与裁剪

- 每次成功推送生成新版本 `v(N+1).tar.bz2`，写 `latest.json`，然后**删除超出最近 7 份的旧快照**（保留 v(N-6)..v(N+1) 共 7 个）。
- 7 份历史即「回滚/灾备」：设置页可「历史版本」查看/回滚到其中任一份。
- 裁剪是 best-effort：服务器删失败不影响本次同步成功，下次再清。

---

## 7. 合并算法

### 7.1 基本记法
每条记录 = `(key, updatedAt, deviceId, data)`；比较「谁更新」：先比 `updatedAt`（大者新），相等再比 `deviceId`（字典序大者胜，保证确定性）。

### 7.2 集合类实体（favorites / recent / progress / settings / songs）
- 按 `key` **并集**。
- 同 key 双方都有：取「更新者」的 `data`。
- 应用墓碑：`deletedAt > updatedAt` 的条目删除。
- `recent` 合并后按 `played_at` 降序截断到本机上限 500。
- `settings` 只在云白名单内参与；合并后本机已有的值若「本机更新」则保留（避免把用户刚改的偏好打回）。
- `songs` 写回策略：**只补缺 + 更新元数据（title/artist/album/duration/cover_url），不动 `play_url` / `lyric_url` / `local_path`**（地址类字段由本机按来源重新解析，避免把过期 URL 写进来）。

### 7.3 歌单（playlists）
- 按 `id` 合并（B2：id 创建时生成、全局统一，重命名只改 name 不动 id）。
- 同名但 id 不同 = 两张不同歌单，**不静默合并**（P3 加「发现同名歌单，是否合并」提示）。
- 因此 `play_progress.queue_id` 与 `settings.last_queue` 不需要随同步改写。
- 曲目集：按 `song_key` **并集**；被墓碑删除的曲目剔除。
- 顺序：以 `modified_time` 较新的那份为主序列；仅在另一份中出现的曲目**追加末尾**（追加顺序按各自 position）。
- 结果写回时重排 `position`，并更新 `playlist_songs.updated_at`（§13）。

### 7.4 覆盖模式（仅手动「恢复云快照 / 历史版本」可选）
- 先按目标快照清空本地对应分区，再写入快照内容（等价于现有 `BackupImportMode.overwrite`）。
- 覆盖后把本地「已知版本」重置为目标 `version`，**并清空本机对应用户可重加的墓碑**（避免覆盖后又被旧墓碑删掉）。

### 7.5 冲突计数（给 UI 展示）
「冲突」定义为：某 key 在本次「云端快照 vs 本地」之间**双方都改过且 `data` 不同**。合并仍然自动完成，但计入 `conflicts` 计数并在「冲突明细」列出（key、实体、两侧 updatedAt），供用户查看（默认不阻断）。

---

## 8. 多设备模型

### 8.1 deviceId 与设备列表
- 首次运行生成 `sync_device_id = UUIDv4`，存 `settings`（设备本地，不入云）。
- 推送时把自己的 `{id, name, lastSeenAt}` 合并进 `latest.json.devices`（每台设备可让用户起个名，默认取主机名/机型）。
- 设备列表用于：调试展示、tombstone 回收判定（可选）。

### 8.2 时间与时钟偏差
- 记录时间统一用 `updatedAt(ms, UTC)`。
- 已知风险：设备本地时钟偏差会造成「旧覆盖新」。**缓解**：
  - 首次连接时读 WebDAV 响应 `Date` 头，与本机钟差 `skew` 记录到状态；偏差 > 阈值（如 5 分钟）在 UI 提示，但**不自动改本机时间**。
  - 墓碑保留 90 天远大于常见偏差，接受极端情况下的「删除回流」为已知限制（文档记录，不静默）。

### 8.3 乐观并发写（防两端同时推）
1. 推送前 GET `latest.json`，记 `version = N`。
2. 与本地「上次已知 version」比较：不同 → 先下载 `vN` 快照并与本地合并（§7），得到最新合并态。
3. 合并前先应用墓碑：`deletedAt > updatedAt` 的记录删除；asset 墓碑明确指示对应资产文件被删。
4. 用合并态打包新快照 `v(N+1).tar.bz2` 并 PUT。
5. PUT `latest.json`（先再确认远端 version 仍为 N 再写；`If-Match` ETag 若服务器支持）。若被别的设备抢先（变了）→ 重下最新、重合并、重试（有限次）。
6. 成功后裁剪超出 7 份的旧快照。

### 8.4 首次同步与设备生命周期
| 场景 | 行为 |
|---|---|
| 远端为空（首台） | MKCOL 建目录 → 打包本机全量 → 推 `v1.tar.bz2` → 写 `latest.json` |
| 新设备接入 | 远端有数据 → **先拉后合**（不覆盖本地）；无本地数据则直接落地最新快照 |
| 用户在设置里「重置同步」 | 清远端 `resonance-sync/`（或改名归档）→ 本机重新全量推 v1 |
| 设备作废 | 无需专门操作；旧设备若再上线，其数据按正常合并回流（墓碑保护删除） |

### 8.5 本地基线快照与墓碑生成
- 本机保留「上次同步成功的基线快照」（压缩存于 App 私有目录，体积≈一份 `tar.bz2`）。用途：
  1. **无变更检测**：基线内容指纹 == 当前内容指纹 → 不生成新版本、不上传。
  2. **墓碑生成**：基线有、当前无的记录 → 生成 `tombstones` 项；凡被删除的记录/资产都要能从「基线 → 当前」差异推导出来。
  3. **合并基线**：与云端快照 diff 时作为「本地上次状态」。
- **DB 被清后强制重建基线（关键边界）**：schema bump 重建 / 用户清库 / 本地数据损坏后，**删除本地基线**并**以当前（可能是空的）状态作为新基线**，不能拿旧基线去 diff、也不能把「空库」当成「全删了」。否则同步层会把云端数据批删。

### 8.6 tombstone 回收
- 墓碑随 `snapshot.json` 携带；每次生成新快照时清理 `deletedAt` 早于「本机时间 − 90 天」的墓碑（默认 90，可配）。
- 因保留最近 7 份快照，误删可从历史版本恢复；「重置同步」时清空全部墓碑与历史。

---

## 9. 安全

### 9.1 凭据存储
- `baseUrl / username / password` 存**系统安全存储**（Android Keystore / iOS Keychain / Windows DPAPI / macOS Keychain），经 `flutter_secure_storage` 之类实现，**不写设置明文**、不入云、不进日志。
- 建议界面引导用户用「应用专用密码」（坚果云/Nextcloud 均支持），不要用主账号密码。

### 9.2 明文上传的风险与缓解（用户已选明文）
- 风险：WebDAV 服务器 / 网盘方可读到明文，且**订阅 URL 里可能含 token**。
- 缓解（本期落文档、实现按此提示）：
  1. 强制 HTTPS；连接时校验证书（默认信任系统根，不跳过）。
  2. UI 明确提示「数据以明文存于你的 WebDAV，请使用专用账号 + 应用密码」。
  3. 订阅 URL 与 cookie/token 类字段单独标注为敏感，日志脱敏（只打域名，不打 query）。
  4. **后续可选升级**：端到端加密（口令派生密钥，只加密快照内容体）——留接口，不在本期。

### 9.3 敏感项清单
`subscriptions/index.json`、订阅展开的规则 URL、`source_enabled_*` 关联的源配置、`search_history`。

---

## 10. 触发时机与设置项（**这些设置全为设备本地，不入云**）

| 设置键 | 默认 | 说明 |
|---|---|---|
| `sync_enabled` | `false` | 总开关，**默认关**，用户手动开 |
| `sync_startup_pull` | `true`（开启后） | 启动 / 回前台自动拉取 |
| `sync_debounce_seconds` | `30` | 数据变更后防抖推送 |
| `sync_wifi_only` | `true` | 自动同步仅 Wi-Fi |
| `sync_interval_minutes` | `0` | 定时同步；`0=关`，**自定义数值**（分钟，建议 15~10080 即最长一周）；**仅前台/启动补跑** |
| `sync_remote_root` | `/resonance-sync` | 远端目录 |
| `sync_last_at` / `sync_last_status` | — | 状态（只本机） |
| `sync_device_id` / `sync_device_name` | — | 设备标识（只本机） |
| `sync_debounce_dirty`（运行时） | — | 待推送脏标记（只本机） |

- **不引入 workmanager**：定时只在前台 Timer / 启动 / 回前台时补跑（未打开的设备靠「下次启动」补同步）。这与「默认全关 + 省电 + 零平台依赖」一致。
- **变更感知（决策 33）**：在 `packages/db` 的 **6 个参与同步的 DAO 写后发统一变更事件**（songs/playlists/favorites/recent/progress/settings；下载任务属设备本地不发），`packages/sync` 订阅并按 `sync_debounce_seconds`（30s）防抖触发推送；与数据变化解耦、实时。
- **单飞锁**：同一时刻只允许一个同步任务；触发若已有任务在跑，则标记待再跑，结束后补一次。

---

## 11. 模块落点与接口

### 11.1 新包 `packages/sync`
```
packages/sync/
  pubspec.yaml            # 依赖 core, db, webdav_client_plus, archive(tar/bzip2), crypto
  lib/
    sync.dart             # 导出
    src/
      dav_client.dart     # abstract DavClient（GET/PUT/DELETE/PROPFIND/MKCOL, ETag）
      dav_client_impl.dart# 基于 webdav_client_plus 的实现（DavClient 接口隔离）
      sync_engine.dart    # 编排：下载最新 → 合并 → 应用 → 打包推送 → 裁剪 7 份
      snapshot_codec.dart # 快照 tar.bz2 读写、snapshot.json 编解码、sha256
      merge.dart          # 纯函数合并（§7），可单测
      entities.dart       # 各实体 provider：DB/文件 ⇄ SnapshotRecords
      latest.dart         # latest.json 编解码
      assets_tree.dart    # 资产文件树 ⇄ 快照包内 assets/
      secure_store.dart   # 凭据读写（壳工程注入实现）
      sync_config.dart    # sync_* 设置项
```

### 11.2 关键接口（草案）

```dart
/// WebDAV 客户端抽象：只暴露同步需要的原语，便于替换实现与测试
abstract class DavClient {
  /// 列目录（不存在返回空）
  Future<List<DavEntry>> list(String path);
  /// 读文件（404 返回 null）
  Future<List<int>?> read(String path);
  /// 写文件，可带乐观并发 ETag
  Future<void> write(String path, List<int> bytes, {String? ifMatch});
  /// 删除文件/目录（不存在忽略）
  Future<void> delete(String path);
  /// 建目录（递归）
  Future<void> mkdir(String path);
}

/// 同步引擎：把各 provider 与 DavClient 组合起来
class SyncEngine {
  /// 自动同步：永远合并；推送新快照并裁剪到 7 份
  Future<SyncReport> sync();

  /// 手动恢复「当前云快照」：可选 合并 / 覆盖
  Future<SyncReport> restore({required bool overwrite});

  /// 历史版本（最近 7 份）：列出 / 回滚到指定版本
  Future<List<SnapshotVersion>> listVersions();
  Future<SyncReport> restoreVersion(int version, {required bool overwrite});

  /// 重置同步：清远端后重推本机
  Future<void> resetRemote();
}

/// 一次同步的结果（喂给 §14 的 UI）
class SyncReport {
  final int pulled;            // 应用到的记录数
  final int pushed;            // 推上去的新版本号（无变更可为空）
  final int? fromVersion;
  final int? toVersion;
  final int conflicts;         // §7.5
  final bool success;
  final String? error;
  final DateTime at;
}
```

> `SecureStore` 与文件读写等平台能力由**壳工程注入**（与现有 `FilePickers` 注入思路一致），`packages/sync` 保持不直接依赖平台插件。

---

## 12. 与现有备份功能的关系

- **并存**：本地「数据备份 / 导入」保留（离线与隐私场景仍需本地文件）。
- **复用**：同步层复用 `BackupService` 的分区模型与 `BackupCodec` 的记录结构 / 版本校验；新增的是 `packages/sync` 的「多设备合并 + 快照链传输」。
- **区别**：
  - 备份 = 单文件整包、人工、`merge/overwrite`、无历史。
  - 同步 = 快照链（全量压缩、留最近 7 份）、自动、永远合并（手动恢复才可覆盖）、带 tombstone 与 deviceId。

---

## 13. 表结构改动（schema 升 v5）

**原则**：遵循项目既有「删旧表重建 + onOpen 幂等补表（或 bump 版本），不迁移旧数据」的策略。

| 表 | 改动 | 理由 |
|---|---|---|
| `playlist_songs` | **新增 `updated_at INTEGER NOT NULL DEFAULT 0`** | 记录级合并需要「曲目增删/顺序变更的时间」；歌单整单判定用 `max(updated_at)` + 「有序 song_key 列表」指纹 |
| 其余表 | 不改 | favorites/recent/playlists/settings/songs/progress 均有可用时间列（§1.1-5） |

- `kDbVersion` 4 → **5**。
- 歌单顺序变化的检测：写回时更新该歌单所有行的 `updated_at`；合并时用「有序 song_key 列表」的哈希作辅助指纹，防止顺序变化但时间未变而漏检。
- 现有备份 `resonance-backup` v1 结构不变（不含 `playlist_songs.updated_at`，导出时按需取当前时间兜底）。

---

## 14. UI 设计（设置页「云同步」区块）

```
云同步
  [开关] 启用云同步
  WebDAV 地址  [https://…            ]  用户名 [        ]  密码 [••••]  [测试连接]
  上次同步：2026-11-19 11:20 · 成功（v41 → v42，冲突 1）
  状态：○ 正常   ● 冲突 1   ● 失败：401 未授权
  [立即同步]  [恢复云快照…]  [重置同步]
  历史版本：v42（当前） / v41 / v40 / …（近 7 份，可查看/回滚）
  时机：☑ 启动/回前台拉取  ☑ 变更后自动推送(30s)  ☑ 仅 Wi-Fi   定时 [自定义 __ 分钟]
  冲突明细 ▸（展开：实体 / 键 / 两侧时间）
```

要素：总开关、连接配置 + **测试连接**、上次同步时间与状态、立即同步、恢复云快照（弹层选合并/覆盖）、**历史版本回滚**、重置同步、时机设置、冲突明细。错误原因要可见（对齐「结论要有证据」）。

---

## 15. 测试方案（真实环境，不用 mock）

1. **单元测试（纯逻辑）**：`merge.dart` 覆盖并集/取新/墓碑/歌单顺序/冲突计数；`snapshot_codec` 的 tar.bz2 往返 + sha256 校验 + 损坏包拒绝；`latest` 编解码；时钟平手用 deviceId 的确定性；**7 份裁剪**（第 8 次推送后最旧被删）。
2. **端到端（真实 WebDAV）**：测试内用 `shelf_dav` 起**真实 WebDAV 服务器**，跑真实 `PUT/GET/PROPFIND/MOVE/DELETE`，模拟两台设备（两个 `SyncEngine` + 两份独立临时 DB）：
   - 首台推 `v1`、第二台拉合推 `v2`；
   - 并发写（先改后推 vs 先推）→ 乐观并发后不丢；
   - 删除传播（A 删 B 同步后也删）；
   - 歌单顺序合并；
   - 资产文件新增/修改/删除镜像（快照包内 `assets/`）；
   - 回滚到 `v(N-2)`；
   - 重置同步。
3. **真机手验**：连坚果云 / Nextcloud 各跑一遍「首台→第二台→改→回传」，截图留证（放入 `docs/evidence/`）。
4. 遵循「测试先行 + 每改动 analyze + 全量测试」。

---

## 16. 实施边界 / 本期不做

- 不做端到端加密、不做音频文件同步、不做服务端、不做 workmanager 后台定时、不做多 WebDAV 账号并存（单账号）。
- 不做 CRDT；冲突默认自动合并 + 计数提示，不做逐条手工裁决。
- iOS 上 `applicationSupportDirectory` 内的资产镜像行为需真机确认后再实施（见 §19-1）。

---

## 17. 验收标准（真实环境）

1. 两台设备（同数据）接通同一 WebDAV → 各自改收藏/歌单 → 双向同步后**两端一致、无重复、无丢失**。
2. A 删除一首收藏 → B 下次同步后也删除（墓碑生效）。
3. 两设备同时改同一歌单 → 曲目并集、顺序以更新者为准、冲突计数 ≥1 且可查看。
4. 新设备首次接入 → 先拉后合，不覆盖本机已有数据；空远端首台 → 正常推送。
5. 断网改数据 → 恢复网络后补推成功，无重复。
6. 「恢复云快照」选覆盖 → 与云端一致；选合并 → 不丢本机新数据。
7. 凭据不在明文设置/日志中出现；错误码（401/404/超时）在 UI 可见并可重试。
8. 单元测试 + `shelf_dav` 端到端测试全绿；`dart analyze` 0 issue。
9. 连续同步 8 次后云端只剩最近 7 份快照，且能回滚到其中任一份。

---

## 18. 决策记录（2026-11-19 逐轮拍板）

| # | 决策 | 选择 |
|---|---|---|
| 1 | 产出形态 | 只出「调研 + 设计文档」，不写代码 |
| 2 | 数据范围 | 元数据 + 订阅源相关（源开关/自定义配置/规则资产/歌曲索引/搜索历史） |
| 3 | 传输 | WebDAV 当哑存储会合点 |
| 4 | 同步粒度 | **快照链（全量压缩，保留最近 7 份）+ latest 指针** |
| 5 | 实体内部合并 | 恢复操作时可选 覆盖 / 合并；自动同步合并且按记录合并 |
| 6 | 设备标识 | 稳定 `deviceId` + `updatedAt(ms)` + `deviceId` 兜底 |
| 7 | 触发 | 做成设置项；这些设置项不入云 |
| 8 | 安全 | 系统安全存储存凭据 + 上传明文 |
| 9 | 合并/覆盖落点 | 自动永远合并；手动「恢复云快照/历史版本」可选 |
| 10 | 删除 | 墓碑随快照携带，合并时执行 |
| 11 | 目录布局 | 快照链 `snapshots/vNNNN.tar.bz2` + `latest.json` |
| 12 | 首次接入/生命周期 | 远端空→推本机；新设备→先拉后合；可「重置同步」 |
| 13 | 并发 | 推送前 GET 版本，变了先拉回合并再推（乐观并发） |
| 14 | 大对象/资产 | 资产文件原样打进快照包（tar）的 `assets/` |
| 15 | 与备份关系 | 并存、复用分区模型与 codec |
| 16 | 模块落点 | 新建 `packages/sync` |
| 17 | 同步 UI | 开关+时间+状态+立即/恢复/历史/重置+冲突明细 |
| 18 | 触发默认值 | 默认全关，用户手动开 |
| 19 | 测试设施 | `shelf_dav` 起真实 WebDAV 服务器 |
| 20 | 后台定时 | 不引 workmanager，仅前台/启动补跑 |
| 21 | 表结构 | `playlist_songs` 加 `updated_at`，schema → v5 |
| 22 | WebDAV 客户端 | 选用 `webdav_client_plus` |
| 33 | 变更感知 | db 层统一变更总线 + sync 订阅防抖 |
| 34 | 基线与墓碑 | 本地保存上次同步基线快照；diff 生墓碑、指纹同则不上传 |
| 35 | 资产删除判定 | 仅墓碑算删除；远端有本地无只补不发 |
| 36 | songs 写回 | 只补缺+更新元数据，不动 play_url/lyric_url/local_path |
| 37 | schema v5 | 按约定 bump + 删表重建（清本地数据） |
| 38 | 实现分期 | P1 引擎+实体；P2 资产/订阅树；P3 UI+历史回滚 |
| 39 | 损坏回退 | 依次回退 v(N-1)…，全败则报错不覆盖 |
| 40 | 单飞锁 | 同一时刻一个同步任务，结束补一次 |
| 41 | HTTP | 默认仅 HTTPS；localhost/私有网段可放行 http 并警告 |
| 42 | songs.lyric | 快照不含歌词正文，只含 lyric_url |
| 43 | 歌单身份 | B2：id 全局统一、按 id 合并；重命名保留，同名独立创建不合并 |
| 23 | play_device | 不入云，设备本地 |
| 24 | download_* 偏好 | 入云 |
| 25 | 定时间隔 | 自定义数值（分钟），默认关 |
| 26 | iOS 资产镜像 | 行为一致、需真机验证（见 §19-1） |
| 27 | iOS 落地 | 统一 `getApplicationSupportDirectory` + 真机验证 + 排除系统备份 |
| 28 | 同步模型 | **①' 快照链 + 合并 + 墓碑，保留最近 7 份** |
| 29 | 快照内容 | 单 tar.bz2 包 = `snapshot.json`（全部实体 + 墓碑）+ `assets/` 文件树 |
| 30 | 墓碑保留 | 随快照携带，默认 90 天回收；7 份历史兜底误删 |
| 31 | 压缩 | **tar + bzip2 -9（11.70x，纯 Dart 全平台）** |
| 32 | 记录结构 | 维持原样（实测改结构对压缩率无收益） |

---

## 18.5 权限与可靠性（默认值，可改）
- **损坏/缺失快照**：依次回退 `v(N-1)`…，取最近可解压者；全失败则报错，不覆盖本地（可手动「以本机为准重建」）。
- **HTTP 策略**：默认仅允许 HTTPS；`localhost` / 私有网段（如 AList 局域网）可显式放行 http 并在 UI 警告（可行性已在 §19 记入实测项）。
- **`songs.lyric` 正文**：快照只含 `lyric_url`，不含歌词正文（可回源、省体积）。
- **快照 schema 兼容**：更高 schema 版本拒绝写入、提示升级 App；更低版本按老结构兼容读。

---

## 19. 实施期验证清单（不阻塞设计，落地前逐项实测）

1. **iOS 真机**：`getApplicationSupportDirectory` 下的「建目录→写→读→删除→再读」；并决定是否对该目录加「不参与系统备份」（iOS `NSURLIsExcludedFromBackupKey`、Android backup rules），避免与 WebDAV 双来源。
2. **曲库体积实测**：数千曲时 `snapshot.json` 原始大小、`tar.bz2` 后大小、7 份占用 → 确认对目标 WebDAV 无压力（合成 5000 曲已实测约 252KB/份，待真曲库复核）。
3. **webdav_client_plus 协议实测**：在坚果云 / Nextcloud / AList 上的 `PUT/GET/PROPFIND/DELETE/MKCOL`、`ETag/If-Match` 支持情况、大文件分块/超时行为。
4. **裁剪降级**：服务器不支持原子删除或并发删除失败时，7 份裁剪的 best-effort 处理与提示。
5. **压缩选型复核**：`archive` 4.7.1 的 `BZip2Encoder/TarEncoder` 在 Android/iOS 真机的编码耗时（桌面 0.55s，移动端预估 1.5~2.5s）；以及 `archive` xz 编码器 no-op 的版本确认。