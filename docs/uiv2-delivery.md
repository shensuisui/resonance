# uiv2 交付说明 —— 「回响 Resonance」界面 v2

> 交付物：`packages/uiv2`（Flutter UI 包）+ 壳工程入口 `fm_app/lib/main_v2.dart`。
> 目标平台：Windows 桌面；同一套代码覆盖 手机 / 平板 / 桌面 三种断点。

## 1. 数据接线：mock 已全部移除

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
| 运行日志 | 假日志 | `SourceLogBus`（真实源执行记录，200 条环形缓冲） |

**接线修正（v1 遗留缺陷）**：
- `main_v2.dart` 补了 `SourceManager.initAll()` —— v1 从未调用，导致 LocalScanSource 的 `search()` 恒空；
- 补了 `assets/plugins/` 随包插件加载（v1 遗漏）；
- 演示曲库源与本地/规则/插件源同构，可在「音乐源」页启停。

## 2. 页面清单（17 个）

首页 / 搜索 / 音乐库 / 我喜欢的音乐 / 本地音乐（+文件夹详情）/ 我的 / 专辑 / 艺人 /
歌单详情（真实增删改）/ 全部歌单 / 最近播放 / 下载任务 / 音乐源 / 订阅 / 运行日志 / **设置（新增）**。

交互：播放条三区（移动端单区+细线进度）、沉浸播放页（模糊封面+歌词舞台+逐行高亮跟随+手动滚动 4 秒后回跟）、
播放队列（拖拽排序 onReorderItem + 移除 + 2 秒撤销 toast）、睡眠定时器、播放设备、曲目菜单、
新建/重命名/删除歌单、扫描目录输入、清空最近播放/搜索历史。

## 3. 验证结果

- `flutter analyze`：packages/uiv2 **0 error / 0 warning / 0 info**；fm_app 同样干净。
- `flutter build windows --debug -t lib/main_v2.dart`：成功。
- 运行实测（driver 模式）：应用启动、首页显示**真实最近播放**（本机数据：山水之间/幻听/若把你）、
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

## 5. 测试（packages/uiv2/test/，见 test/README.md）

```text
00:03 +118: All tests passed!
```

| 文件 | 例数 | 覆盖 |
|---|---|---|
| catalog_test.dart | 21 | 配表派生（16 专辑/曲目总数/艺人排序）、时长哈希稳定性与 148~361 范围、格式化边界、来源归属/本地标记 |
| catalog_source_test.dart | 25 | 源 id、search 空/命中/分页/hasMore、详情抛错、getSongUrl 恒空串、演示歌词、歌单/专辑接口 |
| lyrics_test.dart | 14 | 三态装配（lrc/demo/none）、时间轴算法（lead=5、span、空行不计时）、activeLyricIndex 扫描语义 |
| icons_test.dart | 6 | 38 个图标全渲染 + heart/user 两条历史回归直测（小数连写 FormatException / 相对 s 命令死循环） |
| providers_test.dart | 31 | 主题/Wi-Fi/音量/搜索历史持久化、收藏快照写入、歌单 CRUD 全链路、队列操作、假 Player 计数 |
| widgets_test.dart | 9 | 9 类组件冒烟 + 回调断言；repeat 动画固定帧（禁 pumpAndSettle） |
| sleep_timer_test.dart | 5 | fakeAsync：每秒递减/到点 pause/cancel/覆盖重设/dispose 清理 |

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
cd G:\works\shelli\fm\fm_app
G:\works\shelli\fm\.fvm\flutter_sdk\bin\flutter.bat run -d windows -t lib\main_v2.dart
# 日常验证
G:\works\shelli\fm\.fvm\flutter_sdk\bin\flutter.bat analyze
cd ..\packages\uiv2 && G:\works\shelli\fm\.fvm\flutter_sdk\bin\flutter.bat test
```

## 7. 已知问题与后续建议

1. **驱动 tap 导航有一拍延迟**：driver tap 后立即截图，内容区偶显示上一个页面（侧栏高亮即时正确）。
   人工点击无此现象。疑似 driver 事件与帧回调的时序问题，待排查（不影响人工使用）。
2. ~~播放条 2px 溢出~~ 已修：进度条行改 Flexible 吸收压缩，复检无溢出警示（08-home-fixed.png）。
3. **构建前先结束 fm_app 进程**：否则 WebView2Loader.dll 被占用导致 MSB3021（Windows 老坑）。
4. **sub_page 订阅**：uiv2 通过 SubscriptionHost 注入对接订阅库，壳工程尚未装配该宿主，页面会显示明确说明而非假数据。
5. **建议后续**：补 `SourceManager` 对 getPlaylistSongs/getPlaylistList 的透传；插件源歌词 lines 为空的 crawler 侧修复；下载任务持久化。
