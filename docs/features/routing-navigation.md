# 路由栈与返回逻辑（现状审计）

> 审计时间：2026-11-27。范围：`packages/uiv2` 的 go_router 结构、`navProvider` 门面、系统返回、转场动画。
> 结论：结构本身是清晰的（6 分支 + 二级页），但「**层级关系**」与「**用户来路**」被混为一谈，加上返回动画在 12% 处被截断，导致体感混乱。

---

## 1. 路由结构（事实）

```
GoRouter
└─ StatefulShellRoute.indexedStack          ← 外壳：侧栏/底栏/播放条 + 6 个保活分支
   ├─ /home                                  HomePage
   ├─ /search                                SearchPage
   ├─ /library                               LibraryPage
   │   ├─ /library/playlist?p=ID             PlaylistPage
   │   └─ /library/playlists                 PlaylistsPage
   ├─ /liked                                 LikedPage
   ├─ /local                                 LocalPage
   │   └─ /local/folder?p=NAME               FolderPage
   └─ /profile                               ProfilePage
       ├─ /profile/recent                    RecentPage
       ├─ /profile/downloads                 DownloadsPage
       ├─ /profile/sources                   SourcesPage
       ├─ /profile/subs                      SubsPage
       ├─ /profile/logs                      LogsPage
       └─ /profile/settings                  SettingsPage
```

- 一级页 = 分支（`NoTransitionPage`，切 tab 即时、各自保活）。
- 二级页 = 挂在所属分支下的子路由（`CustomTransitionPage`，进入内容区，外壳/播放条不动）。
- 参数一律走查询参数 `?p=`（`::`、`/` 不转义丢失）。
- 页面跳转唯一入口：`navProvider.notifier.go(name, param)`（全项目约 49 处）。
- **所有 go 都调用 `router.go(location)`**（`router.dart:190`），不是 `push`。
- `NavState.trail` 字段从未写入（`grep` 仅定义/copyWith），返回栈信息实际上不存在。
- 沉浸播放页、弹层、Sheet 不是路由：前者是外壳内 overlay（Provider 控制），后者走根 Navigator。

## 2. 返回逻辑（事实）

| 入口 | 实现 | 实际行为 |
|---|---|---|
| 顶栏返回（手机/平板浮动） | `navProvider.back()` | `router.canPop()` 为真则 `pop()`；否则 `go(kParentRoute[current] ?? 'home')` |
| 侧栏/品牌行返回（桌面） | 同上 | 同上 |
| Android 系统返回 | 外壳 `PopScope(canPop:false)`（`app_shell.dart:151`） | ① 沉浸播放页开 → 收起；② 当前非移动端一级页 → `nav.back()`；③ 一级页 → 2 秒内再按退出 |
| 二级页上的系统返回 | 该分支 Navigator 默认 pop | 与顶栏返回走同一个 `CustomTransitionPage` 反向动画 |
| Sheet/Dialog 上的返回 | 根 Navigator pop | 先于外壳被消费 |

返回目标由 **路由父子关系**（`kParentRoute`）决定，而不是用户实际来路。

## 3. 体感“混乱”的具体来源（代码可证）

1. **跨分支跳转丢来路**（最核心）
   - 首页 → 最近播放：`/home` → `go('recent')` 变成 `/profile/recent`；返回 → `/profile`（我的），不是首页。
   - 首页/我的 → 歌单列表/歌单详情：返回 → 音乐库。
   - 音乐库 → 音乐源/订阅/日志/设置：返回 → 我的。
   - 播放条 → 下载任务：返回 → 我的。
   - 歌单内「查看全部歌单」`go('playlists')` 会**替换**当前歌单页：返回 → 音乐库，原歌单不见了。
   - 同一路由之间互跳（歌单 A → 歌单 B）同样是替换，返回只能回分支根。

2. **高亮与返回目标不一致**
   - `kNavFor['recent'] = 'home'`（`router.dart:93`）：最近播放页底部高亮「首页」，但返回却去「我的」。
   - 手机上「我喜欢的音乐 / 本地音乐」是分支页（`/liked`、`/local`），但底栏没有这两项且 `kNavFor` 映射到自身 → **没有任何 tab 高亮**。
   - 桌面侧栏是 6 项，同一页面在高亮上又与手机不同。

3. **返回栈是假的**
   - `NavState.trail` 永远为空；`needsBack()` 只看当前路由名，不看“是否真的能回去”。
   - 顶栏返回与系统返回不是同一实现路径（顶栏走 `nav.back()`，二级页系统返回走 Navigator pop；一级页由 PopScope 接管），行为细节容易分叉。

4. **go 的“替换”语义被当成 push 用**
   - 注释说“go 二级页压栈”，但 `router.go` 是按 URL 重建匹配栈：同级页面互跳会丢掉上一页，不是真正的压栈。
   - 依赖 `currentConfiguration.uri` 的标题/高亮只能反映“当前在哪”，无法表达“从哪来”。

## 4. 转场动画（现状与“怪”的原因）

实现：`app_router.dart:_subPage`

- 时长：前进/返回都 `UiV2Motion.d2 = 220ms`。
- 前进：内容从 `Offset(0.12, 0)`（手机）滑到 0 + 淡入；宽屏从 `(0, 0.04)` 上浮。
- 返回：同一 Tween 反向 → 当前页从 0 滑到 **12%**；且 `animation.status == reverse` 时**关闭淡入**，整页原样滑走。
- **页面在 12% 位移处就被路由移除**：最后几帧不是“滑出屏幕”，而是“滑了一点然后画面跳掉”。这是“返回有点怪”的直接原因。
- 只做当前页动画，`secondaryAnimation` 完全没用：上一页静止不动，没有 iOS 常见的轻微左移/视差。
- 返回曲线用 `UiV2Motion.exit`（cubic(.4,0,.7,.2)）+ 反向，速度曲线与前进不对称，观感一顿。
- 页面自带 `UiV2RouteSurface` 实底色（防止过渡透字），返回时底色也不淡出 → 结束瞬间整块消失。
- 一级页是 `NoTransitionPage`：切 tab 完全即时，与二级页 220ms 位移形成两套语言。
- Android 预测返回未接入：外壳 `PopScope(canPop:false)` 吃掉系统手势预览；二级页也不是 predictive-back route。

## 5. 改造方案（待拍板）

### 5.1 导航模型（拍板：C 混合）

- **A. 来源优先（history-aware）**：记录每次进入二级页的“来路页”，返回先回来源（跨分支则切回来源分支），高亮也跟着来路。最符合“我从哪来就回哪去”，需要自建一层返回栈（go_router 的 URL 栈不够）。
- **B. 层级固定（branch-parent）**：永远回所属一级页；把高亮统一成 `branchOf(current)`，文档写清“二级页返回=其所属栏目”。实现最小、可预测，但不是用户直觉。
- **C. 混合（推荐）**：同分支内真实压栈/返回上一页；跨分支进入时记录一级来路，返回切回来路分支；同级互跳（歌单 A→B）用 push 保留 A。高亮 = 当前来路分支（无来路时用所属分支）。需要给 `NavEntry` 增加 origin，并改用 `push` + 分支切换 API。

### 5.2 动画（用户暂缓，不实施）

- **A. iOS 式对称（推荐）**：前进整页从右滑入（100%），上一页同步左移 20% + 轻阴影；返回完全镜像（当前页滑出 100%，上一页回位）；280–300ms，前进/返回共用对称曲线。二级页与 tab 仍区分（tab 即时）。
- **B. 轻量修正**：保留 12% 位移，但返回时补完整滑出 + 淡出，并让页面在完全离场后才移除；改动小，只修“跳一下”。
- **C. 统一淡入淡出**：所有二级页 150–200ms 交叉淡化，不再位移；最稳但层级感弱。

### 5.3 系统返回（用户暂缓，不实施）

- 建议顶栏/系统/手势统一到同一个 `nav.back()`（二级页也由外壳统一接管），并评估接入 Android predictive back；至少保证“按返回的落点”与顶栏一致。

## 6. 验证方式（实施后）

- 路由：新增 widget 测试覆盖「首页→最近→返回=首页」「首页→歌单→返回=首页」「歌单A→B→返回=A」「tab 切换后返回」「移动端 liked/local 高亮」。
- 动画：用真实组件录帧（60fps 截图序列/GIF）对比前进/返回首尾帧，确认返回最后一帧完全离场、无跳变；同时提供改前/改后预览。

### 7. 拍板记录（2026-11-27）

- **导航模型：C 混合**（本阶段实施）：
  - 同分支内进入二级页记真实历史，返回上一页（歌单 A→B→返回 A）；
  - 跨分支进入二级页记住来路页，返回切回来路（首页→最近播放→返回首页）；
  - tab 高亮跟随来路（无来路时回落到所属栏目）；
  - 切四个底部 tab 清空历史；桌面侧栏的一级页不显示返回、忽略历史。
- **动画：暂缓**（承认返回在 12% 处移除会跳，但本期不改）。
- **系统返回/预测返回：暂缓**（保持 Navigator 默认 pop；后续再统一落点）。
