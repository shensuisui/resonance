# uiv2 交付说明 —— 「回响 Resonance」界面 v2

> 交付物：`packages/uiv2`（Flutter UI 包）+ 壳工程入口 `resonance_app/lib/main.dart`。
> 目标平台：Windows 桌面；同一套代码覆盖 手机 / 平板 / 桌面 三种断点。

## 1. 数据接线：mock 已全部移除

> ⚠️ **迁移前快照**：本节与下表描述「内置配表 → 真实能力」的第一次迁移；2026-11 这些内置能力（CatalogMusicSource/16 专辑配表/演示歌词/WAV）已整体外移为 demo_source 独立服务，现状见 §8。

上一版 uiv2 的页面直接读内置配表（16 张专辑的 `catalog.dart`）。本次改造：

| 数据 | 上一版（mock） | 本版（真实能力） |
|---|---|---|
| 曲目/专辑/艺人 | 配表内存表 | 包装成真实音乐源 `demo_catalog`（`CatalogMusicSource implements MusicSource`），注册进 SourceManager |
| 收藏 | 内存 Set | `FavoritesDao`（含 title/artist/cover 快照，写库后重载） |
| 最近播放 | 内存数组 | `RecentPlaysService`（recordPlay + getRecentPlayRecords，快照直渲染） |
| 自建歌单 | 配表 | `PlaylistDao` 全套 CRUD（新建/重命名/加歌/移歌/删除，全部带快照） |
| 本地音乐 | 配表 local 标记 | `LocalScanSource.getScannedSongs()`（按 `localPath` 父目录分组） |
| 搜索 | 配表过滤 | `SourceManager.searchAll`（真实聚合已启用源）+ 搜索历史（settings JSON，与 v1 同键） |
| 歌词 | 演示配表 | `SourceManager.getLyrics`（源返回什么用什么；演示曲库源内置原创演示歌词作为其真实数据） |
| 下载 | 假进度 | `DownloadManager`（taskStream + cancel/retry/deleteCache/clearFinished） |
| 源启停 | 假开关 | `SourceManager.setSourceEnabled` + settings `source_enabled_<id>` |
| 设置 | 内存 | `SettingsDao`（键名与 v1 ui 包一致：theme_mode/play_mode/search_history…，两版互通） |
| 运行日志 | 假日志 | `SourceLogBus`（真实源执行记录，300 条环形缓冲） |

**接线修正（v1 遗留缺陷）**：
- `main.dart` 补了 `SourceManager.initAll()` —— v1 从未调用，导致 LocalScanSource 的 `search()` 恒空；
- 补了 `assets/plugins/` 随包插件加载（v1 遗漏）；
- 演示曲库源与本地/规则/插件源同构，可在「音乐源」页启停。

## 2. 页面清单（15 个）

首页 / 搜索 / 音乐库 / 我喜欢的音乐 / 本地音乐（+文件夹详情）/ 我的 /
歌单详情（真实增删改）/ 全部歌单 / 最近播放 / 下载任务 / 音乐源 / 订阅 / 运行日志 / **设置**。（共 15 个，无专辑/艺人页）

交互：播放条三区（移动端单区+细线进度）、沉浸播放页（模糊封面+歌词舞台+逐行高亮跟随+手动滚动 4 秒后回跟）、
播放队列（拖拽排序 onReorderItem + 移除 + 2 秒撤销 toast）、睡眠定时器、播放设备、曲目菜单、
新建/重命名/删除歌单、扫描目录输入、清空最近播放/搜索历史。

## 3. 验证结果

- `flutter analyze`：packages/uiv2 **0 error / 0 warning / 0 info**；resonance_app 同样干净。
- `flutter build windows --debug -t lib/main.dart`：成功。
- 运行实测（当时 Flutter driver/集成测试模式；App 现已不注册 flutter driver 扩展，见 uiv2-release-check）：应用启动、首页显示**真实最近播放**（本机数据：山水之间/幻听/若把你）、
  音乐库显示真实歌单、搜索页显示真实搜索历史与演示曲库推荐词、我喜欢的音乐页显示真实收藏（1 首）。
- 图标解析器修复：SVG 路径严格化数字解析（修 FormatException）+ 补 `s` 命令分支（修死循环）+ 迭代上界兜底；
  93 条图标路径全部解析通过。

## 4. 截图（docs/uiv2/screenshots/）

| 文件 | 内容 |
|---|---|
| 01-home-desktop.png | 首页 · 桌面宽屏（真实最近播放 + 推荐歌曲 + 我的歌单） |
| 02-library-desktop.png | 音乐库 · 分段（全部/本地/自建/我最喜欢/演示曲库/6U/枫叶/已下载）+ 真实歌单卡 |
| 03-search-desktop.png | 搜索页 · 真实搜索历史 + 演示曲库推荐词 + 浏览分类 |
| 04-liked-desktop.png | 我喜欢的音乐 · 真实收藏（1 首 · 枫叶音乐来源标签） |
| 06-profile-desktop.png | 我喜欢的音乐 hero 区（宽屏，含播放全部/随机/加入队列） |
| 07-profile-phone.png | 手机断点（480px）：顶栏返回 + 底部 TabBar + 迷你播放条 |
| 08-home-fixed.png | 首页 · 播放条 2px 溢出修复后复检 |
| 09-home-dark.png | 首页 · 深色主题 |

## 5. 测试（packages/uiv2/test/）

> 现状（2026-11 实测）：**39 个测试文件、约 210 个 test/testWidgets**。`catalog_source_test.dart` 与 `test/README.md` 已不存在；原「118 例」为迁移前旧统计。

```text
00:03 +210: All tests passed!
```

| 文件 | 例数 | 覆盖 |
|---|---|---|
| providers_test.dart | 31 | 主题/Wi-Fi/音量/搜索历史持久化、收藏快照、歌单 CRUD、队列、假 Player |
| widgets_test.dart | 12 | 组件冒烟 + 回调断言 |
| play_progress_test.dart | 11 | 播放进度（play_progress）存取 |
| row_marks_test.dart | 10 | 曲目行标记/播放态 |
| captcha_ui_test.dart | 7 | 人机验证 UI（歌曲宝） |
| catalog_test.dart | 7 | 展示元数据模型/设备/睡眠常量（非配表数据） |
| lyrics_test.dart | 6 | 歌词装配/时间轴 |
| icons_test.dart | 6 | 图标渲染 + 历史回归 |

> 完整清单以 packages/uiv2/test/ 实际文件为准。

基建与 ui 包一致：ProviderContainer + addTearDown、InMemoryDatabaseProvider、手写 FakePlayer
（显式实现三条流）、无 mockito。运行：`cd packages/uiv2 && flutter test`

（以下为分项说明）

1. **数据层**：Catalog 配表派生（专辑/曲目/艺人/时长哈希/歌词时间轴）、CatalogMusicSource（search 分页/getSongDetail/getLyrics/getPlaylist*）、makeDuration/formatDurationLong。
2. **Providers**：ThemeMode/WifiOnly/Device/Volume 持久化与恢复、LikedNotifier.toggle 写快照、PlaylistActions CRUD、SearchHistory JSON 往返、PlaybackController（假 Player 计数）。
3. **组件**：UiV2SongRow（渲染/高亮/交互/播放态蒙层）、UiV2Eq/UiV2Spinner（固定帧）、UiV2Cover 兜底、UiV2Button/Chip/Badge/Segmented/Switch/Empty。
4. **图标解析器**：93 条路径全部解析、heart 路径语义断言（回归 .8.8.8 故障）、非法输入不抛异常不卡死。

运行：`cd packages/uiv2 && flutter test`

## 6. 运行命令

```bash
cd G:\works\shelli\fm\resonance_app
G:\works\shelli\fm\.fvm\flutter_sdk\bin\flutter.bat run -d windows -t lib\main.dart
# 日常验证
G:\works\shelli\fm\.fvm\flutter_sdk\bin\flutter.bat analyze
cd ..\packages\uiv2 && G:\works\shelli\fm\.fvm\flutter_sdk\bin\flutter.bat test
```

## 7. 已知问题与后续建议

1. **driver tap 后截图偶见上一页**：主因是 go_router 二级页 220ms 转场期间两页同绘（已由补不透明底色修复）；driver 另有 300ms 固定等待兜底。现行 plan 不含「tap 紧接截图」，不可复现；残留仅为截图无 endOfFrame 保证，属可加固项。
2. ~~播放条 2px 溢出~~ 已修：进度条行改 Flexible 吸收压缩，复检无溢出警示（08-home-fixed.png）。
3. **构建前先结束 resonance_app 进程**：否则 WebView2Loader.dll 被占用导致 MSB3021（Windows 老坑）。
4. **sub_page 订阅**：uiv2 通过 SubscriptionHost 注入对接订阅库；**壳工程已装配**（main.dart 注入 subscriptionHostProvider，见 resonance_app/lib/subscription_library.dart）。
5. **建议后续**：`SourceManager` 仍无 getPlaylistSongs/getPlaylistList 透传（uiv2 已直接调用 MusicSource 接口）；插件源歌词 lines 为空的 crawler 侧修复。（下载任务持久化已于 2026-11-18 完成，见 features/download.md。）


## 8. 演示曲库迁移（2026-11）

演示曲库已从 App 内置实现改为根目录 `demo_source/` 的独立 Dart HTTP 服务，详见 [demo-source.md](../features/demo-source.md)。

- App 内删除 `CatalogMusicSource`、16 张专辑配表、9 首演示歌词与静音 WAV 生成代码（注：`data/catalog.dart` 仍保留展示模型/常量与 demo_catalog id，不含配表数据）；
- 演示封面/音频/JSON 不再进入 Flutter assets；
- Debug 启动时从 `/rule.json` 注册普通规则源，并从 `/catalog.json` 注入展示元数据；服务离线只跳过演示源；
- Release 由 `kDebugMode` 常量分支与 assets 物理缺失双重剔除；
- 数据接口支持 `d=<秒>` 延迟，用于真实复现慢源、超时和加载态。

## 9. 数据导入导出（2026-11 新增）

- 整包备份/还原（resonance-backup v1 JSON，含 playlists / favorites / recent / settings / progress）。
- 单歌单导出（回响 JSON / M3U8 / CSV）。
- 导入预览（合并 / 覆盖）+ 设置白名单；订阅不导出。
- Android「用回响打开 .json」：ACTION_VIEW + MethodChannel，见 resonance_app/lib/file_pickers_impl.dart 与 uiv2 widgets/backup_open_handler.dart。
- 详见 docs/features/data-import-export.md。
