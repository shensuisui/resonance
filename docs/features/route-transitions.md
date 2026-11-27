# 路由转场（iOS 27 卡片推入 + 大屏淡入）

> 状态：移动端卡片推入/拖拽返回、大屏淡入与断点分派已实现；侧边/表单/paged sheet 待接入。
> 关联：[routing-navigation](routing-navigation.md)。

## 1. 移动端（窄屏 < 768dp）：卡片推入 + 全屏拖拽返回

- 路由：`CardPage<T>` → `CardPageRoute<T>`（`packages/uiv2/lib/src/route/card_page.dart`）。
- 弹簧：`pushSpring` 300ms 临界阻尼，初速 9；时长由 `settlingTimeOf` 求出（本机 3.47 库解 449ms，规格估算 459ms）。
- 新页位移 `dx=(1-progress-overdrag)*width`，对齐物理像素；被覆盖页 `-0.3*width*secondary` + 10% 黑遮罩；超椭圆裁剪（`RSuperellipse` + `MediaQuery.displayCornerRadiiOf`）。
- 前缘阴影：4% 黑、sigma 12、stops [0,1/6,1/3,1/2,2/3,1]，仅入场绘制。
- 拖拽：任意位置 30px 起手；`popReach=0.4665`、`popLead=0.35`、flick 1.5→4.25×；反向橡皮筋 0.55/0.5；`navigator.didStartUserGesture` 配对；焦点归还。
- 停稳后清空 transform/clip 图层句柄；`offstage` 覆写为空，避免 HeroController 钉住首帧。
- **不透明底色**：Card/Fade/Root 路由统一包 `RouteSurface`（主题 bg），修复过渡中透出上一页；带单测。
- **拖拽 pop 的 URL**：走壳层 `dragBackPopOverride → NavNotifier.back()`，URL 与混合历史一致；带单测（/profile/settings → /home）。

## 2. 大屏（≥768dp）：原地淡入

- 路由：`FadePage<T>` → `FadePageRoute<T>`，200ms 线性 `FadeTransition`；被覆盖页**完全不动**（不读 secondaryAnimation），无位移/缩放/遮罩。
- 断点分派：`pageFor(context: ...)` 窄屏 CardPage、宽屏 FadePage；错误页同源，不混 MaterialPage。
- tab：仍为 `NoTransitionPage/RootPage`（RootPage 零时长），切 tab 即时。

## 3. 实测

- 模拟器 release：手机 360dp 录屏逐帧可见卡片从右滑入、底层页左移；左→右拖拽可返回。
- 模拟器切 1600×1000（桌面形态）：设置页淡入，底层“我的”页全程不动。

## 4. 待实现（大屏 sheet）

- ✅ `SideSheetRoute`（300/200ms，0.4 视口宽夹 360–560，右侧平移，遮罩同步）——已实现，未替换现有 showUiV2Sheet。
- ✅ `FormSheetRoute`（404ms，1.2→1 缩放 + 淡入，遮罩同弹簧）——已实现，未接入具体表单。
- ⏳ `PagedSheetRoute`（sheet 内二级页复用 CardPageRoute + 尺寸动画）——待实现。
- ⏳ 现有 `showUiV2Sheet` 宽屏路径接入侧边 sheet（需先出视觉预览）；表格/设置表单逐个迁移。
- ⏳ 跨断点掉落重开（桌面 push 后缩窗到 <600 的重放）——待实现。

## 5. 顶栏下沉（手机）

- 手机顶栏从 `app_shell` 移到页面层：`UiV2MobilePageChrome` 包住窄屏路由页，顶栏随页面一起做转场（AppBar 不再瞬换）。
- 按页配置：`kPageHeadRoutes` 的页面（home/search/library/liked/local/recent/downloads/playlist/playlists/sources/subs/logs/settings）已有 PageHead 大标题 → 顶栏 `showTitle=false`，消除双标题；无 PageHead 的页面（如 folder/个人页）顶栏显示标题兜底。宽屏不渲染顶栏，保持页面自带大标题。
- 逐页 before/after（手机 9 页 + 大屏 9 页）像素 diff：大屏 meanAbsDiff 0.00–0.01（仅时钟），手机 0.05–0.53（仅顶栏标题区域），无布局位移。证据：`.dsh/tmp/evidence/compare_mobile.png`、`compare_wide.png`。
