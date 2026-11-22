# 数据导入导出 —— 现状审查与方案

> 结论速览：uiv2 **原无导入导出，现已落地**（详见 §11 实施记录）：整包 resonance-backup JSON 备份/还原 + 单歌单导出，配 Android「用回响打开 .json」。以下为设计过程，实施结果以 §11 为准。

- 日期：2026-11-12
- 审查范围：docs/summaries/summary-s1-s3.md 中「歌单导入/导出 (M3U/PLS/JSON)」与 PRD 3.4

---

## 1. 现状审查

### 1.1 结论：uiv2 没有任何导入导出

- 设置页只有「清空」与「查看」两类操作，没有导出/导入入口（settings_page.dart 全文无 import/export）。
- 歌单详情页没有导出入口；歌单列表页没有导入入口。
- database_helper.dart 与 sqflite_settings_dao.dart 都写了「多设备同步预留」注释，但没实现。

### 1.2 已有的底层能力（来自 v1 遗留）

packages/ui/lib/src/services/playlist_io.dart 提供**单歌单**导入/导出，基于 packages/core/lib/src/services/playlist_codec.dart：

| 格式 | 用途 | 保真度 |
|---|---|---|
| M3U | 最通用，外部播放器 | 有损：忽略 sourceId、localPath、extra、时长 |
| PLS | Winamp | 有损：同上 |
| JSON | 自定义 {name, songs[]} | 有损：只 title/artist/url/localPath，丢 sourceId/song_key/时长 |

v1 的 PlaylistIo 依赖 file_picker（文件选择/保存路径，Android 要 SAF），而 uiv2 **刻意不依赖 file_picker**（settings_page.dart:355 注释），所以这条链在 uiv2 里不可直达。

### 1.3 审查发现的问题点

1. **覆盖面为零**：只有单歌单，收藏/最近播放/设置/播放进度/源开关/订阅全部无法导出。
2. **格式有损**：JSON 也丢了 sourceId/song_key/时长/封面 URL，换源后无法重新解析播放地址、无法显示元数据快照。
3. **入口不可达**：v1 的 UI 入口在已废弃的 packages/ui，uiv2 没有接线。
4. **无版本/合并语义**：没有版本号、没有导入预览、没有「合并 vs 覆盖」。
5. **播放进度已在跑**：play_progress 按队列存了「听到哪」，导出应含进来以便恢复。

---

## 2. 设计目标

1. **一次导出，全部可恢复**：歌单（song_key/sourceId/元数据快照/进度）、收藏、最近播放、设置、订阅、搜索历史。
2. **迁移友好**：手机与桌面任一端都导出一致的备份，换设备或重装一键还原。
3. **降级可读**：单个歌单仍能导出 M3U/PLS/CSV 供其它播放器消费。
4. **版本安全**：导入端根据版本号判断兼容性。

---

## 3. 数据字典（导出内容）

### 3.1 备份文件结构（单个 .json）

```jsonc
{
  "format": "resonance-backup",   // 魔数，识别文件类型
  "version": 1,                    // 结构版本，> 当前版本才拒绝导入
  "exportedAt": "2026-11-12T20:30:00Z",
  "stats": { "playlists": 3, "songs": 6, "favorites": 1, "recent": 3, "settings": 12, "progress": 1 },
  "playlists": [
    {
      "name": "夜行",
      "songs": [
        { "songKey": "gequbao:1", "title": "素颜", "artist": "许嵩", "duration": 259, "coverUrl": null, "localPath": null }
      ]
    }
  ],
  "favorites": [{ "songKey": "gequbao:1", "time": 1690000000000, "title": "素颜", "artist": "许嵩" }],
  "recent": [{ "songKey": "gequbao:2", "playedAt": 1690000000000, "title": "山水之间", "artist": "许嵩" }],
  "settings": { "theme_mode": "dark", "play_mode": "list", "volume": "0.8", "scan_dir": "", "source_enabled_gequbao": "1" },
  "progress": [{ "queueKind": "playlist", "queueId": "p1", "songKey": "gequbao:1", "positionMs": 123000, "updatedAt": 1690000000000 }]
}
```

### 3.2 歌单单项导出（歌单详情页）

| 格式 | 内容 | 用途 |
|---|---|---|
| 回响 JSON（推荐） | song_key/sourceId/元数据/进度 | 换设备完整还原 |
| M3U8 / CSV（uiv2 侧实现） | 可播地址（localPath 优先，否则 playUrl） | 外部播放器 |

---

## 4. 导入语义（合并 vs 覆盖）

| 模式 | 行为 | 适用 |
|---|---|---|
| 合并（默认） | 歌单按 song_key 去重后追加到同名歌单或新建；收藏/最近去重；设置里只写「本机没有的键」（不覆盖已有，见 §11.2） | 日常迁移 |
| 覆盖 | 先清空对应表再写备份内容 | 完全还原某台设备快照 |

- 执行前给「逐项预览」：将新增 / 跳过 / 更新 N 条，确认后才写入。
- 设置白名单：theme_mode、play_mode、volume、scan_dir（本地路径跳过）、source_enabled_<id>。
- 订阅地址（subscriptions）属敏感 URL，**不导出**（不在设置白名单，无开关）。

---

## 5. 目标方案（两层设计）

### 5.1 整包备份/还原（设置 → 数据备份）

新增「数据备份」区块（独立 section，见预览图变体 A）：

| 操作 | 产出 |
|---|---|
| 导出全部数据 | resonance-backup-v1-<日期>.json，含歌单/收藏/最近播放/设置/进度 |
| 从文件导入 | 选文件 → 版本校验 → 选「合并/覆盖」→ 逐项预览 → 执行 |
| 最近一次备份 | 显示备份时间与内容统计（日期 · N 歌单 / M 首），可「分享」 |

### 5.2 单歌单导出（歌单详情页顶栏 … 菜单）

- 格式：回响 JSON（推荐）/ M3U8 / CSV；
- 选项：包含封面（存 URL）与播放进度（默认开）、包含设置项（默认关）；
- 点「导出 N 首」写入文件（桌面存文件、移动端走系统分享/SAF）。

### 5.3 底层落点

- 新增 packages/core/lib/src/services/backup_codec.dart：纯 Dart，Playlist/List<FavoriteRecord>/List<RecentPlayRecord>/settings/progress ↔ JSON（带版本，与现有 PlaylistCodec 并存不破坏）。
- 新增 packages/core/lib/src/services/backup_service.dart：exportAll({now})→BackupDocument；importDocument(doc,{mode,sections})→ImportReport；核心纯逻辑可单测，不碰文件系统。
- uiv2 加轻量「选择备份文件」入口：**已确认（2026-11-12 用户拍板）由壳工程注入 picker 函数**，uiv2 维持零平台依赖，只调用注入的接口。

  **picker 契约（草案；最终实现合并为 saveTextFile，见 §11 差异 1）**：
  ```dart
  /// 壳工程注入的文件选择器（uiv2 只调接口，不依赖 file_picker 等平台包）
  abstract class FilePickers {
    /// 选择要导入的文件（返回路径，取消返回 null）
    Future<String?> pickOpenFile({String title, List<String> extensions});
    /// 选择导出保存位置（返回路径，取消返回 null）
    Future<String?> pickSaveFile({String title, String? suggestedName, List<String> extensions});
  }
  ```
  - 桌面（resonance_app）：用 file_picker 实现；
  - 移动端：Android 走 SAF / 系统分享（share_plus），iOS 走 Files 文档选择器；
  - uiv2 侧新增 `filePickersProvider`（Provider<FilePickers>），测试里注入 stub 即可。
- UI：settings_page.dart 数据区块加「数据备份」子区；歌单详情页 … 菜单加「导出」入口。

---

## 6. 验收标准（真实环境，不用 mock）

1. 导出全部数据 → 换设备/清库重装导入 → 歌单/收藏/最近播放/设置/进度全恢复，列表正常显示标题与封面。
2. 导入旧版本备份 → 提示版本不兼容，数据不动。
3. 导入损坏/非备份文件 → 明确报错且不写任何数据。
4. 合并模式重复导入两次 → 数据不重复（去重生效）。
5. 覆盖模式 → 先清空再写，与备份一致。
6. 歌单详情导出 JSON → 换源解析到播放地址能播放；M3U8/CSV 能直接放进其它播放器。

---

## 7. 本期不做（边界）

- 不导出：本地扫描的音频文件本身（只导路径）、播放缓存文件、下载任务与临时文件、歌词文件（只导引用）。
- 云同步 / 多设备自动同步（PRD 预留 updated_at，本期仅单文件备份）。
- 端到端 / 云盘备份（只做本地文件 + 系统分享）。

---

## 8. 补充：与现有 PlaylistCodec 的关系

backup_codec 是「完整无损」的内网格式，PlaylistCodec 是「对外/降级」的交换格式，两者并存：

- 回首 JSON 备份用 backup_codec（保真）；
- 导给外部播放器用 PlaylistCodec 的 M3U8/PLS；
- 已有 v1 由 PlaylistIo 生成的旧 JSON（无版本号）在导入时按 PlaylistImportResult 兼容解析，标记为 legacy 并尽量映射。


## 9. 决策记录

- 2026-11-12：用户确认「壳工程注入 picker 函数」——uiv2 维持零平台依赖，文件选择/保存由 resonance_app 注入实现。

---

## 10. 「用回响打开 .json」直接导入（Android）

**目标**：在文件管理器/下载列表里点开备份 .json，就能直接进入导入预览，不必先开 App 再选文件。

**实现**
- 清单：`MainActivity` 增加两个 `ACTION_VIEW` 意图过滤器——
  `content/file` + `mimeType=application/json`，以及 `file/content` + `pathPattern=".*\.json"`
  （覆盖系统按扩展名识别的情况）。`launchMode` 已是 singleTop，运行中再次打开走 `onNewIntent`。
- `MainActivity.kt`：MethodChannel `resonance/open_file`
  - `getInitialUri`：冷启动时返回随 Intent 带进来的文件（取一次即清空）；
  - `readText`：用 ContentResolver 读文本（SAF 的 content:// 只有原生层能读）；
  - 运行中收到新 Intent：`invokeMethod("openedUri", uri)` 主动推给 Flutter。
- 壳工程 `ShellFilePickers`：把上述两条路径统一成一个 `openedFiles` 流；
  uiv2 的 `BackupOpenHandler`（包在应用最外层）收到事件后用 `uiV2NavigatorKey` 弹导入预览。

**安全**：导入端只认魔数 + 版本，白名单外的设置键（如 subscriptions）一律拒绝；解析失败只提示不改数据。

---

## 11. 实施记录（2026-11-12）

**已完成**
- core：`backup_codec.dart`（魔数/版本/stats/五分区，含 v1 单歌单兼容）+
  `backup_service.dart`（exportAll、merge/overwrite、白名单过滤、同名歌单合并、本地曲目回写 songs 表）。
- core 测试：`backup_codec_test.dart`（12）+ `backup_service_test.dart`（8），全绿。
- uiv2：`FilePickers` 契约 + `filePickersProvider`；设置页「数据备份」区块（导出/导入/最近一次备份）；
  导入预览弹层（合并/覆盖 + 分区勾选 + 逐项统计）；歌单页「导出歌单」（JSON/M3U8/CSV）；
  `BackupOpenHandler`（系统打开事件）。uiv2 analyze 0 issue，210 项测试全绿（新增 5 项流程测试）。
- 壳工程：`ShellFilePickers`（file_picker 11.0.3；Android 走 SAF/ContentResolver）+ `main.dart` 注入。

**与第 5 节草案的差异（按实现修正）**
1. picker 契约合并为 `saveTextFile(...)`：Android SAF 只给 content:// 句柄，必须由能访问
   ContentResolver 的壳工程「选择+写入」一次完成；分开的 pickSaveFile/writeTextFile 在移动端不可行。
2. merge 模式下设置只写「本机没有的键」：本机已有选择优先，避免导入把用户刚改的主题/音量打回去
   （用户拍板：备份是恢复，不是覆盖当前偏好）。
3. `file_picker` 锁 `^11.0.3`：13.x 经 file_picker_linux→dbus 要求 xml>=6.6.1，与 expr 的
   xml ^6.5.0 冲突，解析不过。

**需要真机验证**
- Android 上「文件管理器点开 .json → 回响 → 导入预览」的整条链路（本机无 adb，且 APK 构建受
  sqlite3 原生库 GitHub 下载限制阻断，见 05 文档第 9 节）。


## 12. v2 统一实现（2026-11-22）

备份与云同步已统一到 `packages/portable`（记录模型 + Reader/Applier/Merger），维度与合并语义一致：

- **格式**：`.zip` 容器，内含 `backup.json`（v2 记录式）与可选 `assets/`；仍兼容读取旧 v1 `.json`（歌单 id 按名字推导、时间取 `exportedAt`、`deviceId=legacy`）。
- **订阅/源**：`subscriptions`（URL、别名、sourceId **及规则原文**）默认随备份与云同步；换机后订阅页可见，点「检查更新」时用落盘规则离线展开；用户安装的 rules/plugins 文件仍走可选资产（默认不含）。
- **维度**：songs 索引 / 歌单 / 收藏 / 最近 / 进度 / 设置（可移植键）；设备本地设置（`scan_dir`/`play_device`）与资产文件（subscriptions/rules/plugins）为**可选分区，默认不含**。
- **合并**：`merge` 按 `updatedAt` 判胜（新覆盖旧、旧跳过，并集写回）；`overwrite` 先清空所选分区（歌曲索引只并集、不删除，避免破坏本地关联）。
- **代码**：`packages/portable`（模型/编解码/归档/服务）← `sync` 复用三件套；`uiv2` 备份流程改二进制 `.zip`，导出前可选「包含资产 / 设备本地设置」。
- **验证**：portable 27 项、uiv2 227 项（含备份流程 5 项）、sync 45 项（含 `backup_vs_sync_test`：备份导入结果 == 云同步结果）；全量 12 模块 0 失败。
