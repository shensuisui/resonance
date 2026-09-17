# fm UI 改进方案（对标 PixelPlayer）

| 文档版本 | 1.3 |
| :--- | :--- |
| 更新日期 | 2026-08-24（会话日） |
| 状态 | 已按用户拍板更新，待细化确认 |
| 对标项目 | https://github.com/PixelPlayerHQ/PixelPlayer（Jetpack Compose / Material 3 Expressive，Kotlin） |
| 分析方式 | 代码级对比（PixelPlayer 克隆于 .dsh tmp 目录，逐文件阅读 UI/theme/presentation 源码） |

---

## 决策记录（v1.0 → v1.1）

| # | 待确认事项 | 用户拍板 | 计划处理 |
| :--- | :--- | :--- | :--- |
| 1 | 播放 Sheet 是否单独立项 | **是** | 独立立项：P0 里程碑，先状态机后视觉（见 2.6） |
| 2 | 内置展示字体 | **先不要** | 本期不做，从分期中移除，预留后续 |
| 3 | 均衡器是否进本期 | **不要** | 移除；阶段三 14 项仅保留睡眠定时器 |
| 4 | 主题色预设 + 全局圆角是否做成设置 | **加入设置参数** | 设置页外观分组新增「主题色」「全局圆角」两项，持久化 settings 表（见 2.1 / 2.3） |

**v1.1 → v1.2 细化决策**：

| # | 细化事项 | 用户拍板 | 计划处理 |
| :--- | :--- | :--- | :--- |
| 1 | 封面取色驱动的作用范围 | **仅播放页/迷你条背景 + 专辑/歌单详情页** | 不做全局配色跟随；见 2.1 / 2.4 |
| 2 | 主题色预设 8 色 + 自定义取色器 | **照此定** | 8 色预设（hex 存储）+ 自定义取色器入口 |
| 3 | 全局圆角默认 12、范围 0~32 | **照此定** | 见 2.3 |
| 4 | 播放 Sheet 立项顺序 | **这个后做** | 单独立项不变，启动顺序后置：先完成阶段一，再启动 M1（见 2.6 / 4） |
| 5 | 引入 cached_network_image 依赖 | **同意** | 阶段三 11 项按计划引入 |

**落库方式确认（读码结论）**：settings 表为 key-value 结构（`database_helper.dart` `kCreateSettingsTable`，`SqfliteSettingsDao`），现有 `theme_mode` 即按 `get('theme_mode') / set('theme_mode', v)` 存取。因此新增「主题色」「全局圆角」**只需新增 key，不改表结构、不升 DB 版本、不重建表**（`ThemeModeNotifier` 即参照模板，`providers.dart` L301）。

---

## 0. 结论摘要

fm 的 UI 架构（Riverpod + Material 3 + 常量主题 + 响应式导航）方向正确，但**视觉表现力、播放器交互、加载反馈**三个维度与 PixelPlayer 差距最大。差距本质不是"缺页面"，而是**缺沉浸感与动效细节**：

| 维度 | PixelPlayer | fm（现状） | 差距 |
| :--- | :--- | :--- | :--- |
| 主题 | Material You 动态取色 + 专辑封面色驱动全 UI | 固定 deepPurple 种子色 | 大 |
| 播放器 | 全局底部 Sheet（迷你条→拖动多级展开）+ 波浪进度条 + 标题跑马灯 | push 全屏页 + 标准 Slider | **极大** |
| 列表 | 骨架屏 + 图片缓存 + 滑动操作 + 长按多选 + 撤销 | 网络图直连 + 基础 ListTile | 大 |
| 导航 | 3 主 root + 侧边抽屉 + 共享轴转场 | 5 tab（搜索/发现/最近/歌单/设置） | 中 |
| 动效 | spring 转场 / 按压微交互 / 触觉反馈 | 基本系统默认 | 大 |

---

## 1. 差距分析（代码级）

### 1.1 主题与视觉体系

**PixelPlayer**（`ui/theme/Theme.kt`）：
- Android 12+ 优先 `dynamicLight/DarkColorScheme`（壁纸取色）；提供品牌色兜底（紫/粉/橙 三主色体系）。
- 支持 `colorSchemePairOverride`：**按当前专辑封面主色生成整套亮/暗 ColorScheme**，播放时全 App 配色跟随封面（`ColorSchemeProcessor.kt`）。
- 形状分级 8/16/24dp；状态栏/导航栏透明、边到边、icon 亮度按底色亮度自动切换。
- 设置项：全局圆角可调、导航栏样式可调（`NavBarCornerRadiusScreen.kt`）。

**fm**（`packages/ui/lib/src/theme/app_theme.dart`）：
- `ColorScheme.fromSeed(seedColor: deepPurple)` 固定种子色；亮/暗两套由 settings 表 theme_mode 切换。
- 间距/圆角常量体系（AppSpacing / AppRadius）已具备，但圆角粒度偏碎（4/8/12/16/24），未按 M3 形状语义分级。
- 默认字体、无动态取色、无封面驱动。

### 1.2 信息架构与导航

**PixelPlayer**：Home / Search / Library 三个主 root（`MainRootRoutes.kt`）+ 侧边抽屉（`AppSidebarDrawer.kt`）+ 底部导航；共享轴转场（`Transitions.kt` `aospSharedAxis`）；支持"启动落在哪个 tab"配置。

**fm**（`app_shell.dart`）：竖屏底部 NavigationBar 5 tab（搜索/发现/最近/歌单/设置），横屏 NavigationRail；页面转场全默认 MaterialPageRoute。**设置/源管理这类低频管理页占了底部主位置**，而"最近播放"这种行为列表单独占一个 tab，权重失衡。

### 1.3 播放器（差距最大）

**PixelPlayer**（`UnifiedPlayerSheetV2.kt` + `FullPlayerContent.kt`）：
- 播放器是**全局覆盖层**：迷你条 → 向上拖动展开全屏 Sheet，多级展开、spring 弹性、predictive back、速度追踪手势（`SheetVerticalDragMath.kt` 等一整套 scoped 状态机）。
- 自定义 `WavyMusicSlider`：播放时轨道上波浪律动，拖动时 thumb 圆点变竖线并放大，已播放段隐藏（`hideInactiveTrackPortion`）。
- `AutoScrollingText`：长标题跑马灯 + 两端渐变淡出，仅展开时滚动。
- 歌词独立 Sheet：模糊封面背景、当前行高亮放大、浮动工具栏、歌词编辑/搜索。
- 队列 Sheet：拖拽排序 + 滑动删除 + SnackBar 撤销（`QueueSheetController.kt` / `DismissUndoBar.kt`）。
- 播放/暂停按钮：图标形态动画切换 + 触觉反馈（`AnimatedPlaybackControls.kt`）。

**fm**（`player_page.dart` / `mini_player.dart`）：
- 迷你条点击后 **push 全屏页**，与主界面割裂；无拖动展开、无过渡动画。
- 标准 `Slider` 进度条，无播放态反馈。
- 标题 ellipsis 截断。
- 歌词视图（`lyrics_view.dart`）已有高亮 + 自动居中，但无背景沉浸。
- 队列页（`queue_page.dart`）为只读列表，不可排序/删除。

### 1.4 列表、加载与反馈

**PixelPlayer**：`SmartImage`（Coil 缓存 + 占位/失败态）、`ShimmerBox` 骨架屏、`PlayingEqIcon`（正弦波形）、`ExpressiveScrollBar`、多选底部栏（`MultiSelectionBottomSheet.kt`）、滑动删除 + 撤销、触觉反馈（`AppHaptics.kt`）。

**fm**：网络图直连 `Image.network`（无缓存、加载中白屏跳动）、有默认封面占位、SongTile 已有播放中 EQ 动画（不错）、无骨架屏、无多选批量、无滑动操作、无触觉反馈。

---

## 2. 改进方案（分期实施）

按"低成本高感知 → 核心体验 → 组件沉淀"推进，每项给出落地要点与涉及文件。

### 阶段一：视觉基础（P0，改动集中、风险低、观感提升最大）

1. **主题增强：可配置种子色（已拍板：加入设置参数）+ 专辑封面色驱动**
   - **设置参数「主题色」**（settings key `seed_color`，默认 `#673AB7` 深紫）：
     - 预设 8 色（存 hex，自定色与预设统一为 hex 字符串，不硬编码预设 id）：
       深紫 #673AB7（现默认）、靛蓝 #3F51B5、天蓝 #1E88E5、青 #00897B、绿 #43A047、橙 #FB8C00、粉 #E91E63、棕 #8D6E63。
     - 设置页外观分组新增「主题色」：预设色块横排选择 + 「自定义」弹取色器（`showDialog` 内嵌 HSV 取色或系统色盘）。
     - 实现参照 `ThemeModeNotifier`：新增 `SeedColorNotifier`（读/写 settings key `seed_color`），`app_theme.dart` 的 `light()/dark()` 接收种子色参数。
   - **专辑封面色驱动**（已拍板范围：**仅播放页/迷你条背景 + 专辑/歌单详情页**）：封面加载成功 → 主色提取（优先 `palette_generator`，离线自实现"缩略图降采样+量化主色"作备选）→ 得到封面主色，供播放页/迷你条/专辑页/歌单详情页背景渐变使用；**不做**全局配色跟随封面。固定生效，不设设置开关（避免过度设计）。
   - 落地文件：`theme/app_theme.dart`、`providers/providers.dart`（新增 Notifier，build_runner 重新生成）、`pages/settings_page.dart`（外观分组）。

2. **排版升级：引入圆润展示字体 —— 已决策：本期不做**（v1.1 起从分期中移除，仅记录：后续做时内置圆体字体资产 + `textTheme` 覆盖，注意中文字体体积预算）。

3. **圆角分级与全局可调（已拍板：加入设置参数）**
   - `app_radius.dart` 收敛为 M3 语义：small(8)/medium(16)/large(24)，删除碎粒度（4/12 不再使用处一并清理）。
   - **设置参数「全局圆角」**（settings key `corner_radius`，默认 12，范围 0~32，整数）：
     - 设置页外观分组新增滑杆；实现参照 `ThemeModeNotifier` 新增 `CornerRadiusNotifier`。
     - `app_theme.dart` 用 `ThemeData(cardTheme, dialogTheme, bottomSheetTheme, navigationBarTheme, ...)` 统一注入，不逐组件改。
   - 落地：`theme/app_radius.dart`、`theme/app_theme.dart`、`providers/providers.dart`、settings 外观分组。

4. **沉浸式播放页背景（封面色渐变）**
   - 播放页/歌词视图背景改为"封面主色 → 表面色"垂直渐变（`DecoratedBox + LinearGradient`），迷你条与全屏页保持一致；**专辑详情页、歌单详情页头部背景同源取色**；无封面时回退表面色。
   - 落地：`pages/player_page.dart`、`widgets/mini_player.dart`、`widgets/lyrics_view.dart`、`pages/album_page.dart`、`pages/playlist_detail_page.dart`（含 discover 歌单详情页头部）。

5. **转场与微交互**
   - 全局页面转场替换为"淡入+轻微上移/缩放"（`PageTransitionsTheme` 自定义 `PageTransitionsBuilder`），低成本统一所有 push/pop。
   - 按钮/卡片按压微缩放（`AnimatedScale` + `Listener` 或 `InkWell` 反馈）；播放/暂停按钮做图标形态动画。
   - 触觉反馈：播放/暂停、拖动进度条落点用 `HapticFeedback.selectionClick()`。

### 阶段二：播放体验核心（P0/P1，与播放器强相关）

6. **全局播放 Sheet（替代 push 全屏页）—— 已拍板：单独立项，但启动顺序后置（先完成阶段一，再启动 M1）**
   - 目标：迷你条 → 上滑展开全屏播放器，可拖回；播放器覆盖于所有页面之上（`AppShell` 的 `Stack` 顶层挂 `PlayerOverlay`）。
   - **立项拆解（先状态机 → 手势 → 视觉）**：
     - **M1 状态与 provider（先做）**：新增 `PlayerOverlayNotifier`（`providers.dart`）：状态枚举 `hidden / mini / expanded` + 拖动偏移 `dragOffset` + 展开/收起/拖动方法；与现有 `playerProvider` 完全解耦（只读其状态）。迷你条存在性 = 状态 != hidden。
     - **M2 手势与布局**：`AppShell` 改 `Stack`，顶层挂 `PlayerOverlay` widget；迷你条（现有 `MiniPlayer` 改造为 overlay 的一部分）上滑展开、下拉收起；拖动映射 offset + `AnimationController` 弹性收尾（对照 `SheetVerticalDragMath`）；竖屏 Sheet、横屏/宽屏直接用全屏页布局（现有 `PlayerPage` 宽屏逻辑复用）。
     - **M3 视觉打磨**：封面渐层背景（依赖第 4 项取色）、波浪进度条（第 7 项）、跑马灯（第 8 项）、队列 Sheet（第 10 项）接入。
   - 落地：`widgets/player_overlay.dart`（新）、`pages/app_shell.dart`、`widgets/mini_player.dart`（改造）。

7. **自定义进度条（波浪律动样式）**
   - 实现 `WavyProgressBar`：播放中已播放段绘制正弦波动画（`CustomPainter + AnimationController.repeat`），暂停时波平；拖动时 thumb 放大为圆形、隐藏未播放段；语义/无障碍保持 `Slider` 等价。
   - 落地：`widgets/wavy_progress_bar.dart`（新）、播放页与迷你条共用。

8. **标题跑马灯**
   - `ScrollableText` 组件：宽度溢出时延迟 2s 后横向滚动 + 两端渐变遮罩（对照 `AutoScrollingText`）。
   - 落地：`widgets/scrollable_text.dart`（新），用于播放页标题/迷你条标题。

9. **歌词增强**
   - 背景：封面模糊（`ImageFiltered + BackdropFilter`）+ 主色暗化渐变。
   - 当前行放大高亮（现有 `LyricsView` 已有高亮/居中，补字号/字重过渡动画即可）。
   - 落地：`widgets/lyrics_view.dart`。

10. **队列 Sheet：排序 + 删除 + 撤销**
    - 基于播放页内的队列入口打开 `QueueSheet`（底部弹层）：`ReorderableListView` 拖拽排序写回 `playQueueProvider`；`Dismissible` 滑出删除；删除后 `SnackBar` 提供"撤销"（暂存被删项，2 秒内恢复）。
    - 落地：`widgets/queue_sheet.dart`（新）、`pages/queue_page.dart` 收敛为 Sheet 或保留页面但加同样交互。

### 阶段三：组件与数据体验（P1/P2）

11. **统一封面组件（缓存 + 骨架 + 占位）**
    - 新增 `CoverImage`：封装 `cached_network_image`（新增依赖）做内存/磁盘缓存；加载中骨架 shimmer（自绘 `ShimmerBox` 或 `shimmer` 包）；失败回退默认封面。
    - 替换现有全部 `Image.network`（song_tile / mini_player / player_page / discover 卡片 / playlist_header）。
    - 落地：`widgets/cover_image.dart`（新）+ 各调用点；`ui/pubspec.yaml` 加依赖。

12. **列表滑动操作 + 长按多选**
    - 搜索结果/歌单详情：`Dismissible` 支持"喜欢/加入歌单/下载"快操作（方向按平台习惯）。
    - 长按进入多选模式（顶部计数 + 批量加入歌单/批量下载/批量移除），对照 `MultiSelectionBottomSheet`。
    - 落地：`widgets/song_tile.dart` 扩展 + `widgets/selection_bar.dart`（新）。

13. **空状态 / 错误状态升级 + 撤销交互**
    - `EmptyState` 增加插画式图标层 + 主操作按钮（如"去搜索""去添加源"）。
    - 歌单删除/歌曲移除统一"SnackBar + 撤销"。

14. **睡眠定时器（已拍板：不做均衡器，仅保留此项）**
    - 播放页菜单项，倒计时暂停/停止；纯 UI + 定时器，成本低。
    - 落地：`pages/player_page.dart` 或播放 Sheet 菜单。

15. **发现页首页化（可选产品向）**
    - 发现页顶部加入"最近播放"横滑区 + 快捷入口（搜索/源管理），把低频管理页从底部 tab 挪进设置或抽屉，主 tab 收敛为 4 个（搜索/发现/歌单/我的）。

---

## 3. 技术落地要点汇总

| 项 | 新增依赖/配置 | 主要涉及文件 | 预估风险 |
| :--- | :--- | :--- | :--- |
| 1 主题色设置 | settings key `seed_color`（+可选 palette_generator） | theme/app_theme.dart, providers/providers.dart, settings_page.dart | 低（provider 隔离，key-value 免改表） |
| 3 圆角设置 | settings key `corner_radius` | app_radius.dart, app_theme.dart, providers/providers.dart, settings_page.dart | 低 |
| 4 封面渐层背景 | 无（依赖封面主色） | player_page.dart, mini_player.dart, lyrics_view.dart | 低 |
| 5 转场/微交互 | 无 | app_theme.dart（PageTransitionsTheme）, 公共按钮 | 低 |
| 6 播放 Sheet | 无（自绘） | widgets/player_overlay.dart, app_shell.dart, mini_player.dart | **中高**；后置启动（阶段一完成后） |
| 7 波浪进度条 | 无（CustomPainter） | widgets/wavy_progress_bar.dart | 中 |
| 8 跑马灯 | 无 | widgets/scrollable_text.dart | 低 |
| 9 歌词增强 | 无 | lyrics_view.dart | 低 |
| 10 队列 Sheet | 无 | widgets/queue_sheet.dart, queue_page.dart | 中 |
| 11 封面缓存 | cached_network_image | widgets/cover_image.dart + 全调用点 | 低 |
| 12 滑动/多选 | 无 | song_tile.dart, selection_bar.dart | 中 |
| 13 撤销 | 无 | playlist 相关页 | 低 |
| 14 睡眠定时器 | 无 | player_page.dart / 播放 Sheet 菜单 | 低 |
| 15 首页化 | 无 | discover_page.dart, app_shell.dart | 低 |

**本期不做（已拍板）**：内置展示字体（原 2）、均衡器（原 14 内）。

**架构约束（贴合 AGENTS.md）**：
- 主题/播放器覆盖层状态放 `packages/ui` 的 providers，业务不落到 `fm_app` 壳工程。
- 新增组件全部沉淀 `packages/ui/lib/src/widgets/`，遵守"颜色走 Theme、间距走 AppSpacing、圆角走 AppRadius"既有约定。
- 设置项一律走 settings 表 key-value（新增 key 免改表/免升版本），不硬编码特例。
- 阶段一先出主题 provider + 单页验证，再扩散。

## 4. 优先级建议

- **先做**：1（主题色设置）、3（圆角设置）、4（封面渐层背景）、5（转场微交互）、8（跑马灯）—— 单点改动，观感立涨。
- **先行**：1（主题色设置）、3（圆角设置）、4（封面渐层背景，含专辑/歌单详情页）、5（转场微交互）、8（跑马灯）—— 单点改动，观感立涨，互相独立可并行。
- **后置**：6（播放 Sheet，已立项）—— 待阶段一完成后启动，按 M1 状态机 → M2 手势 → M3 视觉推进；7、9、10、11、12 随其后（11 依赖已获准的 cached_network_image）。
- **远期**：14、15 及 PixelPlayer 的统计/标签编辑/跨设备等（超出本期 UI 范围）。

## 5. 参考源码对照（PixelPlayer 克隆位置）

克隆目录：`.dsh tmp`（会话环境 `C:\Users\Admin\.dsh\profiles\web\tmp\PixelPlayer`，`git clone --depth 1`）
- 主题：`app/src/main/java/com/theveloper/pixelplay/ui/theme/{Theme,Color,Shape,Type,ColorRoles}.kt`
- 播放器 Sheet：`presentation/components/UnifiedPlayerSheetV2.kt`、`presentation/components/player/FullPlayerContent.kt`、`presentation/components/scoped/SheetVerticalDragMath.kt`
- 波浪进度条：`presentation/components/WavyMusicSlider.kt`
- 跑马灯：`presentation/components/MarqueeText.kt`
- 队列 Sheet/撤销：`presentation/components/QueueBottomSheet.kt`、`DismissUndoBar.kt`
- 图片缓存/骨架：`presentation/components/{SmartImage,ShimmerBox,OptimizedAlbumArt}.kt`
- 首页/库/搜索：`presentation/screens/{HomeScreen,LibraryScreen,SearchScreen}.kt`
- 多选：`presentation/components/MultiSelectionBottomSheet.kt`

---

## 实施进度

### 已完成（阶段一）

- **[x] 1 主题色设置**：`SeedColorNotifier`（settings key `seed_color`，hex 存储）+ 8 色预设（`kSeedColorPresets`）+ HSV 自定义取色器（`color_picker_dialog.dart`）+ 设置页「外观」分组色块选择；`FmApp` watch 种子色重建主题。
- **[x] 3 圆角设置**：`CornerRadiusNotifier`（settings key `corner_radius`，默认 12、范围 0~32）+ `AppTheme` 注入 card/dialog/bottomSheet；设置页「外观」分组滑杆。
- **[x] 4 封面渐层背景**：新增 `CoverBackground` 组件（封面主色 → 表面色垂直渐变，300ms 过渡）；`CoverPalette.resolveColor`（NetworkImage + ImageStreamListener + 模块级 LRU 缓存 64）；接入播放页（body 背景）、迷你条（渐变背景 + 顶部分隔线替代阴影）、专辑页（头部区块，首曲封面取色）。歌单详情页（本地/发现）此前已实现（PlaylistHeaderView + CoverPalette）。
- **[x] 5 转场微交互**：`FadeSlidePageTransitionsBuilder` 全局统一转场（淡入+上移+缩放，全平台注入 `pageTransitionsTheme`）；`PressableScale` 按压缩放组件（按下 0.96 回弹，120ms）接入播放页大播放按钮与发现页歌单卡片；触觉反馈（播放/暂停按钮、进度条拖动结束 `HapticFeedback.selectionClick`）。
- **[x] 8 跑马灯**：`ScrollableText` 组件（溢出检测 → 延迟 2s → 横向往返滚动 + 两端渐变遮罩），接入播放页标题与迷你条标题。
- 新增：`packages/ui/lib/src/widgets/color_picker_dialog.dart`、`packages/ui/lib/src/widgets/cover_background.dart`、`packages/ui/lib/src/widgets/pressable_scale.dart`、`packages/ui/lib/src/widgets/scrollable_text.dart`、`packages/ui/test/theme_settings_test.dart`（17 用例）、`packages/ui/test/widgets/cover_background_test.dart`（3 用例）、`packages/ui/test/widgets/pressable_scale_test.dart`（2 用例）、`packages/ui/test/widgets/scrollable_text_test.dart`（2 用例）
- 验证：ui 包全量 72 测试通过；ui / fm_app analyze 无 error/warning。

**阶段一全部完成。**

### 已完成（阶段二）

- **[x] 6 播放 Sheet**（已立项，M1→M2→M3 推进）：
  - M1 `PlayerOverlayNotifier` 状态机（hidden/mini/expanded + dragOffset + settle 阈值 120px），与 playerProvider 解耦
  - M2 `PlayerOverlay` 覆盖层：迷你条↔全屏播放器拖动切换（AnimationController 展开进度 0~1，上滑跟手/松手 settle，迷你条点击展开替代 push），AppShell Stack 挂载（竖屏迷你条停靠导航上方）
  - M3 接入：封面渐层背景（阶段一 4）、跑马灯（8）、波浪进度条（7）、队列 Sheet（10）
- **[x] 7 波浪进度条**：`WavyProgressBar` 播放中正弦波浪律动、拖动 thumb 放大、点按/拖动 seek（播放页/迷你条接入）
- **[x] 9 歌词增强**：封面模糊背景 + 表面色半透明罩 + 当前行 200ms 字号过渡
- **[x] 10 队列 Sheet**：`QueueSheet` 拖拽排序 + 左滑删除 + SnackBar 撤销（播放页入口改 Sheet）
- 新增测试：player_overlay_test（6+4）、wavy_progress_bar_test（4）、lyrics_view_test（4）、queue_sheet_test（3）
- 验证：ui 包全量 93 测试通过；analyze 无 error/warning。

**阶段二全部完成。**

### 已完成（阶段三）

- **[x] 11 统一封面组件**：`CoverImage`（cached_network_image 缓存 + ShimmerBox 骨架 + 音符占位）替换全部封面 Image.network（song_tile/mini_player/player_page/discover 卡片/playlist_header）；新增测试假 PathProvider。
- **[x] 12 列表滑动 + 多选**：SongTile onLongPress；搜索页长按多选（计数 + 批量加入歌单/下载），左滑快速「加入歌单」（confirmDismiss 弹回）。
- **[x] 13 空态 + 撤销**：EmptyState 插画层 + 主操作按钮（歌单空态加「新建歌单」）；歌单移出/删除 SnackBar 撤销。
- **[x] 14 睡眠定时器**：SleepTimerNotifier（15/30/60/90 分钟倒计时，到点暂停）；播放页菜单显示剩余时间。
- **[x] 15 发现页首页化**：最近播放横滑区 + 音乐源管理快捷入口 + 推荐歌单网格（CustomScrollView）；tab 收敛未做（产品决策另议）。
- 验证：ui 包全量 106 测试通过；analyze 无 error/warning。

**阶段三全部完成。** 本期 UI 改进（阶段一~三）已全部落地。

### 待做（阶段一）

- 全部完成 ✅（1 主题色 / 3 圆角 / 4 封面渐层 / 5 转场微交互 / 8 跑马灯）

## 已确认决策（v1.2，无未决项）

1. 封面取色作用范围：**播放页/迷你条背景 + 专辑/歌单详情页**（不做全局配色跟随；固定生效不设开关）。
2. 主题色预设：**8 色照此定**（深紫/靛蓝/天蓝/青/绿/橙/粉/棕，hex 存储），**保留自定义取色器**。
3. 全局圆角：**默认 12、范围 0~32** 照此定。
4. 播放 Sheet：**单独立项但后置**——先完成阶段一，再启动 M1（状态与 provider）→ M2（手势与布局）→ M3（视觉打磨）。
5. 阶段三 11 项：**同意引入 `cached_network_image`**。
