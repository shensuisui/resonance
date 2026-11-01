# 回响 Resonance 原型 · 逆向结构化规格

> 来源（全部只读，未修改）：
> - assets/app.js（3797 行，单个 IIFE，'use strict'，无模块/无构建/无网络）
> - index.html（275 行，固定 DOM 外壳 + 内联 SVG sprite）
> - assets/styles.css（1010 行，设计令牌 + 全部断点）
> - .file-versions/0eb547304658805aad788d32/manifest.json（20 个版本，currentVersionId = db7c269d-5f4d-4572-8ead-10d5b4d180bf）

**技术形态**：单页 hash 路由；所有页面内容由 JS 字符串拼接后 innerHTML 注入 #view；数据全部内置（16 张专辑），派生数据在启动时构建；播放进度由 250ms 定时器模拟（原型不含音频文件）。

**版本演进要点（manifest）**：v2 歌词逐行高亮 → v3 歌单/我喜欢的/搜索页补全 + 手机端布局 → v4 点击交互 → v6 恢复音量条与静音键 → v9 多源聚合搜索、音乐库改为歌单、行尾标签重新设计、修正上一/下一曲图标 → v10–v12 返回键与 tabbar 层级、平板浮动返回键、播放条封面正方形 → v15/17/18 播放条三区结构 + 平板布局（封面 / 控件行 / 工具区） → v20 基础 button 补 padding:0、修复搜索框双 X。

---

## 1. 路由表

解析：parseHash() → 取 hash 去掉前缀 '#/'，按 '/' 切分；name = parts[0] || 'home'；param = decodeURIComponent(parts.slice(1).join('/'))。默认（空 hash）= home。

| hash 路由 | 渲染函数 | topbar 标题（TITLES / 动态） | ≤767 手机 | 768–1023 平板 | ≥1024 桌面 | 手机 tabbar | 导航高亮(NAV_FOR) | 队列 context |
|---|---|---|---|---|---|---|---|---|
| #/home | renderHome | 首页 | 无返回(一级) | 无返回 | 无返回 | 显示 | home | — |
| #/search | renderSearch | 搜索 | 无返回 | 无返回 | 无返回 | 显示 | search | — |
| #/library | renderLibrary | 音乐库 | 无返回 | 无返回 | 无返回 | 显示 | library | — |
| #/liked | renderLiked | 我喜欢的音乐 | 有返回 | 有返回 | 无返回(大屏一级) | 隐藏 | liked | 我喜欢的音乐 |
| #/local | renderLocal | 本地音乐 | 有返回 | 有返回 | 无返回(大屏一级) | 隐藏 | local | — |
| #/profile | renderProfile | 我的 | 无返回 | 无返回 | 无返回 | 显示 | profile | — |
| #/album/:id | renderAlbum | ALBUM_BY_ID[id].title，缺省 '专辑' | 有返回 | 有返回 | 有返回 | 隐藏 | library | 专辑 / 专辑 · 随机 |
| #/playlist/:id | renderPlaylist | getPlaylist(id).name，缺省 '歌单' | 有返回 | 有返回 | 有返回 | 隐藏 | library | 歌单 / 歌单 · 随机 |
| #/artist/:name | renderArtist | param 原文，缺省 '艺人' | 有返回 | 有返回 | 有返回 | 隐藏 | library | 艺人 |
| #/recent | renderRecent | 最近播放 | 有返回 | 有返回 | 有返回 | 隐藏 | home | — |
| #/downloads | renderDownloads | 下载任务 | 有返回 | 有返回 | 有返回 | 隐藏 | profile | — |
| #/sources | renderSources | 音乐源 | 有返回 | 有返回 | 有返回 | 隐藏 | profile | — |
| #/subs | renderSubs | 订阅 | 有返回 | 有返回 | 有返回 | 隐藏 | profile | — |
| #/logs | renderLogs | 运行日志 | 有返回 | 有返回 | 有返回 | 隐藏 | profile | — |
| #/playlists | renderPlaylists | 歌单（页内 h2 = 全部歌单） | 有返回 | 有返回 | 有返回 | 隐藏 | library | — |
| #/folder/:id | renderFolder | folderNameById(id) | 有返回 | 有返回 | 有返回 | 隐藏 | local | — |
| 其它 | notFound('页面走丢了') | 未找到 | 有返回 | 有返回 | 有返回 | 隐藏 | 无 | — |

关键常量（app.js 1178–1251）：
- ROOT_WIDE = ['home','search','library','liked','local','profile']（大屏一级页，桌面/平板不出返回键）
- ROOT_MOBILE = ['home','search','library','profile']（手机一级页）
- TITLES = { home:'首页', search:'搜索', library:'音乐库', liked:'我喜欢的音乐', local:'本地音乐', profile:'我的', recent:'最近播放', downloads:'下载任务', sources:'音乐源', subs:'订阅', logs:'运行日志', playlists:'歌单', folder:'文件夹' }
- NAV_FOR = { liked:'liked', local:'local', album:'library', playlist:'library', artist:'library', recent:'home', downloads:'profile', sources:'profile', subs:'profile', logs:'profile', playlists:'library', folder:'local' }，未列出者用路由名本身。
- PARENT_ROUTE（无来路时的上级）= { album:'#/library', artist:'#/search', playlist:'#/library', playlists:'#/library', folder:'#/local', liked:'#/profile', recent:'#/profile', downloads:'#/profile', sources:'#/profile', subs:'#/profile', logs:'#/profile' }

返回键载体（同一时刻只有一个）：
- ≤767：顶栏 #topbar-back；768–1023：#float-back（position:fixed，left = calc(--rail-w + 16px)，top 16px，内容区让出等高上边距）；≥1024：#brand-back（侧边栏品牌行右侧）。
- 显示规则：hidden = （≤767 看 ROOT_MOBILE）或（≥768 看 ROOT_WIDE）包含当前路由名。
- goBack()：navTrail.pop() → 继续弹出与当前 hash 相同的项 → target = 栈顶；无来路则 PARENT_ROUTE[name]；再没有则 '#/home'。navTrail 上限 24，仅在 hash 真正变化时入栈。
- render() 末尾：document.title = title + ' · 回响 Resonance'；onRoute() 里 #view.scrollTop = 0 且 window.scrollTo(0,0)。
- 手机二级页：document.body.classList.toggle('is-sub', !ROOT_MOBILE.includes(name))，CSS 里 body.is-sub .tabbar{display:none}。

---

## 2. 每个页面的内容结构（自上而下）

通用构建块：
- pageHead({title, sub, action, cls}) → header.page__head > (div > h2.page__title + p.page__sub) + action
- sectionHead(title, href, linkText='查看全部') → div.section__head > h3.section__title + a.section__link
- rail(html) → div.od-rail.rail style="--od-gap:16px"（横向滚动，scroll-snap-type: x proximity，子项 flex:0 0 auto）
- grid-cards：CSS grid-template-columns:repeat(auto-fill,minmax(148px,1fr))；卡片宽 172px（≥1440 为 188px；卡片内 .card--wide 236px / 258px）
- trackList：单列 div.tracks（gap 2px），行结构见下

### 2.1 曲目行 trackRow(t, index, opts)
opts = { showArt, showAlbum, showSource, hl, emptyTitle/emptyText/emptyIcon }
- 容器 div.track[.is-current][.is-playing][.is-pending][.track--art] data-id
- 三段 grid：minmax(0,1fr) auto auto
- 左：button.track__hit（data-act=play-track, data-id, data-index, aria-label='播放：'+标题）
  - 非 showArt：span.track__idx data-num（当前曲目显示 eq 三柱动画）
  - showArt：coverTag = span.track__cover > img.track__cover-img（无封面时 span.track__cover--empty + i-note icon）+ span.track__cover__state 状态蒙层（data-state: '' | spin | eq）
  - span.track__text > span.track__title.od-truncate（搜索页走 hl 高亮 mark.hl）+ span.track__meta
    - span.track__artist.od-truncate = showAlbum===false ? 艺人 : '艺人 · 专辑'
    - 徽标：t.downloaded 时 span.badge title="已下载"（i-check + 已下载）
    - span.track__src.od-nowrap = sourceName(t.src || 'local')（showSource===false 时不显示）
- 中：span.track__dur = fmt(duration)（m:ss）
- 右：span.track__actions > heartBtn（aria-label '喜欢' / '取消喜欢'，icon heart / heart-fill）+ 按钮 data-act=track-menu aria-label='更多操作：'+标题（i-more）

### 2.2 卡片
- albumCard：div.card > div.card__art > a.card__art-link[href=#/album/id][aria-label='标题，艺人，年份'] > img[alt='标题 专辑封面']；button.card__play[data-act=play-album][aria-label='播放专辑：'+标题]；div.card__body > a.card__name = 标题，span.card__meta = '艺人 · 年份'，span.card__meta = 'N 首 · 流派'
- playlistCard：a[href=#/playlist/id] > span.pl-mosaic（4 张封面图，不足用 p.colors[0] 色块补齐）；user 歌单加 span.badge.badge--glass.pl-card__badge = '我的'；button.card__play[data-act=play-playlist][aria-label='播放歌单：'+名称]；body：名称 / desc（od-clamp-2）/ 'N 首'
- artistCard：封面用 albums[0].cover；aria-label=艺人名；button[data-act=play-artist][aria-label='播放艺人：'+名]；meta = 'N 张专辑 · M 首歌'

### 2.3 #/home 首页（3 个区块）
1. pageHead：标题 '下午好，今天想听点什么？'；副标题 = 已启用源数 N>0 ? '已启用 N 个音乐源 · 手机与大屏同一套界面。' : '所有音乐源都已停用，去「音乐源」重新打开一个。'；右侧按钮 '搜索歌曲' → #/search（btn btn--soft，i-search）
2. sectionHead('最近播放', '#/recent', recently.length ? '查看全部' : null) → rail，最多 8 个 card.card--wide（236px）：封面跳专辑、播放键 data-act=play-track、标题=曲目名、副标题=艺人。空：panel + emptyState('还没有最近播放','点开任意一首歌，它会自动出现在这里。','clock', 按钮 '去找首歌' → #/search)
3. sectionHead('推荐歌曲', null, '') → panel > tracks，数据 = SEED_RECOMMEND（8 首），trackRow(showArt:true)。空：emptyState('暂时没有推荐','推荐来自已启用的音乐源，全部停用时这里为空。','globe', 按钮 '管理音乐源' → #/sources)
4. sectionHead('我的歌单', '#/playlists', mine.length ? '全部歌单' : null) → rail，store.userPlaylists 前 8 个 playlistCard。空：emptyState('还没有自建歌单','把喜欢的歌收进一个歌单，方便下次直接播。','queue', 按钮 data-act=new-playlist '新建歌单')

### 2.4 #/search 搜索
- pageHead('搜索歌曲', '一次搜索所有已启用的音乐源，结果聚合展示，每行标出来源。')
- div.search-sticky > div.searchbar[role=search]：i-search + input#search-input[placeholder='搜索歌曲'][aria-label='搜索歌曲'][autocomplete=off] + button#search-clear[data-act=clear-search][aria-label='清空搜索']（无文字时 hidden）
- #search-results：
  - 空关键词（searchIdleHtml）：
    1) 若 store.searches 非空：sectionHead '最近搜索' + 右侧 button.section__link '清空'(data-act=clear-history)，od-cluster 内 chip（i-clock + 词，data-act=use-search）
    2) sectionHead '推荐搜索'：hotSearches() = ARTISTS 前 4 个艺人名 + 补齐到 6 个的流派名（无 i-clock）
    3) sectionHead '浏览分类'：div.cat-grid（2 列，≥768 三列，≥1024 四列）内 button.cat，背景 linear-gradient(140deg, 流派色, color-mix 55% #14171C)，点击即搜该流派
  - 有关键词：
    - div.search__top：p.search__count = '共 <strong>N</strong> 首与「q」相关的歌曲' + button.ghost-mini '清除'
    - 命中集合只含曲目（匹配 title + artist + album，小写包含）；无启用源 → emptyState('所有音乐源都已停用','聚合搜索只查已启用的源。去「音乐源」重新打开一个，或通过订阅添加新源。','globe', '管理音乐源')
    - 0 命中 → emptyState('没有找到「q」','换个关键词试试，或检查拼写。','search', 按钮 '清除关键词')
    - 来源筛选条 div.od-rail.rail.src-rail：chip '全部来源'(data-act=src-filter, data-src=all) + 每个命中源的 chip + 本地组 chip（组名 '本地'）；aria-pressed 标记选中
    - 分组标题：sectionHead(active.length > 1 ? '来自 N 个源' : active[0].name) + span.section__link 'N 首'
    - panel > tracks（showArt + hl 高亮），默认最多 10 条；超过 10 条时底部 button.btn--soft.btn--block data-act=search-more：'显示全部 N 首' / '收起'
    - 该源无命中 → emptyState('这个来源没有「q」的结果','切回「全部来源」看看其它源，或换个关键词。','search')

### 2.5 #/library 音乐库
- pageHead('音乐库','按音乐源分栏浏览歌单，本地文件与在线曲目都在这里。')
- div.segmented[role=tablist]：'全部' + 每个已启用源（tab id = 'src:'+源id，label=源名）+ '已下载'（id=downloaded）；button.seg[role=tab][data-act=lib-tab][aria-selected]
- #library-body：
  - '已下载'：sectionHead('已下载专辑（N）', '#/downloads', '下载任务') + grid-cards（albumCard）+ panel > tracks（已下载曲目，showArt）。无曲目：emptyState('还没有已下载的歌曲','在专辑页或歌曲菜单里点下载，完成的曲目会列在这里。','download')
  - 其它：sectionHead(scope + ' · N 个歌单', '#/playlists', '全部歌单') + grid-cards（playlistCard）。scope = 源名 或 '全部'。空：emptyState('「scope」下还没有歌单','这个来源暂时没有歌单；也可以去「音乐源」启用别的源。','queue','管理音乐源')
  - 每栏展示哪些歌单由配表 SOURCE_PLAYLISTS 决定（fy: pl-today, pl-night-drive / aiting: pl-focus, pl-jazz / yu7: pl-rock-90s, pl-morning）；'全部' 显示所有（含自建）

### 2.6 #/liked 我喜欢的音乐
- 空：pageHead('我喜欢的音乐','自动同步在线与本地曲目') + emptyState('还没有喜欢的歌曲','在任何歌曲上点一下爱心，就会出现在这里。你可以在首页或搜索里找歌。','heart', 按钮 '去首页看看' → #/home)
- 非空：
  1) div.hero：hero__art = pl-mosaic（最后 4 首喜欢曲目的封面，倒序；不足用 var(--accent-soft-2) 色块）；hero__type '收藏'；hero__title '我喜欢的音乐'；hero__meta = 'N 首 · {fmtLong} · 在线 X 首 · 本地 Y 首'；hero__actions：'播放全部'(play-liked, i-play) / '随机播放'(shuffle-liked, i-shuffle) / '加入队列'(liked-queue, i-queue)
  2) div.filter-rail[role=group][aria-label='排序方式']：chip '最近喜欢'/'标题'/'时长'（data-act=liked-sort, data-by, aria-pressed）
  3) #liked-body = panel > tracks（showArt）
- 排序：recent=倒序（后加入的在前）/ title=localeCompare / duration=时长倒序；fmtLong = 'N 分钟' 或 'H 小时 M 分'

### 2.7 #/local 本地音乐
- pageHead('本地音乐', 'N 首 · F 个文件夹 · {fmtLong} · 不消耗流量', action 按钮 '扫描文件夹'(data-act=scan-local, i-folder))
- 非空：panel > div.list，每个 a.list-row[href=#/folder/{f.id}]：span.folder-ico(i-folder) + span.list-row__main（label=文件夹名，hint='N 首 · {fmtLong}'）+ i-chevron-right
- 空：emptyState('还没有本地音乐','选择一个文件夹，回响会扫描其中的音频文件，按文件夹分组。','folder', 按钮 '选择文件夹')

### 2.8 #/folder/:id 文件夹（内层）
- pageHead(cls='page__head--compact')：title = 路径最后一段，sub = 'N 首 · {fmtLong}' + （路径含 '/' 时追加 ' · ' + 完整路径），action '重新扫描'
- panel > tracks（showArt）。未知 id → notFound('这个文件夹不在本地库里')

### 2.9 #/album/:id 专辑（内层）
- hero：hero__art = 封面大图（alt='标题 专辑封面'）；hero__type = '专辑' + （imported 时 ' · 本地'）+（downloaded 时 ' · 已下载'）；hero__title = 标题；hero__meta = '艺人 · 年份 · 流派 · N 首 · M 分钟'；hero__actions：'播放'(play-album) / '随机播放'(shuffle-album) / 下载按钮(toggle-download，文案由 downloadBtnLabel 决定：'下载' / '下载中 N%' / '已下载'，分别配 i-download / i-check)
- h3.section__title '曲目'（style margin-bottom:var(--s-3)）+ panel > tracks（showAlbum:false，副行只显示艺人）
- section '同类型专辑' → rail：同流派专辑优先 + 其它流派补齐，最多 6 个 albumCard

### 2.10 #/playlist/:id 歌单（内层）
- hero：hero__art = pl-mosaic（前 4 首曲目封面，不足用 p.colors[0]）；hero__type = '歌单' + （user ? ' · 我的' : ' · 编辑精选'）；hero__title = 名称（od-clamp-2）；hero__meta = 'desc · N 首 · M 分钟'；hero__actions：'播放'(play-playlist，空列表 disabled) / '随机播放'(shuffle-playlist) /（非空时）'加入队列'(add-playlist-all) / icon-btn data-act=playlist-menu[aria-label='更多歌单操作'][aria-haspopup=dialog]
- user 歌单追加 div.detail-toolbar：'添加歌曲'(playlist-picker, i-plus) + spacer + '重命名'(playlist-rename, i-edit) + '删除歌单'(playlist-delete, ghost-mini--danger, i-trash)
- panel > tracks（showArt）：空态 mine → emptyState('这个歌单还没有歌曲','点「添加歌曲」，从音乐库里挑几首放进来。','queue', 添加歌曲按钮)；非 mine → emptyState('这个歌单暂时没有曲目','稍后再来看看。','queue')
- section（mine ? '其他歌单' : '相似歌单'）→ rail：其它歌单前 6 个
- 未知 id → notFound('这个歌单不存在或已被删除')

### 2.11 #/artist/:name 艺人（内层）
- hero：hero__art = albums[0].cover；hero__type '艺人'；hero__meta 'N 张专辑 · M 首歌'；hero__actions：'播放热门'(play-artist)
- section '专辑' → grid-cards albumCard
- section '热门歌曲' → panel > tracks（showArt，前 8 首）
- 未知 → notFound('没有找到这位艺人')

### 2.12 #/profile 我的
1) div.profile-head：span.avatar '响' + h2.page__title（font-size var(--fs-24)）'听歌的人' + p.page__sub '免费账户 · 在线与本地同步'
2) div.stats（3 列）：a.stat[href=#/liked] 数字=喜欢数 / 文案 '喜欢的歌曲'；a.stat[#/playlists] 歌单数 / '歌单'；a.stat[#/local] 本地曲目数 / '本地曲目'
3) section '我的歌单'(#/playlists, '全部歌单') → panel > list：前 4 个歌单 a.list-row[href=#/playlist/id]（label 名称，hint 'N 首'，i-chevron-right）
4) section '播放与外观'：'深色主题' switch（hint '跟随你的选择，不影响播放'，data-act=toggle-theme，aria-checked，aria-label='深色主题'）；'仅 Wi-Fi 下载' switch（hint '避免消耗手机流量'，data-act=toggle-wifi，aria-label='仅 Wi-Fi 下载'）
5) section '音乐源与订阅'：'音乐源'[#/sources]（hint 'N 个源 · 已启用 M 个'）；'订阅'[#/subs]（hint 'N 条 · 展开出 M 个源'）；'运行日志'[#/logs]（hint '最近 N 条记录' / '暂无记录'）
6) section '空间'：'我喜欢的音乐'[#/liked]（'N 首'）；'本地音乐'[#/local]（'N 首'）；'最近播放'[#/recent]（'N 首 · 上限 500 首'）；'已下载' row（'N 张专辑' + 按钮 '管理' data-act=clear-downloads）；'下载任务'[#/downloads]（hint = downloadSummary()）
7) section '关于'：'回响 Resonance'（hint '版本 1.0 · 响应式原型' + 按钮 '说明' data-act=about）

### 2.13 #/recent 最近播放
- pageHead('最近播放', list.length ? '共 N 首 · 上限 500 首，重复播放会移到最前' : '')
- panel > tracks（showArt）；空 → emptyState('还没有最近播放','点开任意一首歌，它会自动出现在这里。','clock', '去首页看看')

### 2.14 #/downloads 下载任务
- pageHead('下载任务','下载进度、取消、重试与删除缓存都在这里；原型不产生真实文件。')
- #dl-body：空 → emptyState('还没有下载任务','在专辑或单曲的下载入口开始下载，任务会显示在这里。','download')
- 非空：行头（field__hint '共 N 个任务 · {downloadSummary()}' + 有已结束任务时 button.ghost-mini '清理已结束' data-act=dl-clear）+ panel > tracks，每行 div.dl[data-key]：封面 coverTag + dl__text（dl__title / dl__sub / dl__bar[role=progressbar][aria-label='下载进度：标题'] > i 宽度 % / dl__state = DL_STATE[state] +（下载中再加 ' · N%'））+ dl__act（下载中 → '取消'；已完成 → '删除缓存'；其它 → '重试'）
- DL_STATE = { downloading:'下载中', done:'已完成', failed:'已失败', cancelled:'已取消' }
- downloadSummary()：'没有下载任务' 或 '下载中 N · 已完成 N · 失败 N · 已取消 N'（只拼存在的项，' · ' 连接）

### 2.15 #/sources 音乐源
- pageHead('音乐源', 'N 个源 · 已启用 M 个 · 搜索与推荐只使用已启用的源', action '导入插件文件')
- 空：emptyState('还没有音乐源','可通过订阅或导入插件文件添加。','globe', '添加订阅' + '导入插件文件')
- section '已注册源（N）' → panel > list，每行 sourceRow：label=源名，hint='ID {id} · {类型} · {来源归属}'（+ demo 时 ' · 演示展开'），右侧 button.switch[role=switch][aria-checked][aria-label='停用 X' / '启用 X'] + icon-btn data-act=source-menu[aria-label='源详情：X']
- section '添加源' → panel__pad：'通过订阅添加'(sub-add, primary) / '导入插件文件'(source-import) / hint '源与订阅在本原型中只做界面演示，不访问网络，也不伪造远程数据。'

### 2.16 #/subs 订阅
- pageHead('订阅', 'N 条订阅 · 展开出 M 个源', action '添加订阅')
- 空：emptyState('还没有订阅','订阅一个远程地址，会展开成 1~N 个音乐源；也可以直接导入插件文件。','globe', '添加订阅' + '导入插件文件')
- section '订阅列表（N）' → panel > list，每行 subRow：label=subTitle（alias 或类型名），hint=url（od-truncate），hint='{类型} · 展开 N 个源 · {上次检查 MM-DD HH:mm | 从未检查}'，按钮 '检查更新'(sub-check) + icon-btn[aria-label='订阅详情：X']
- section '批量操作' → panel__pad：'检查全部订阅更新'(sub-check-all) + hint '演示模式：不会联网，只更新「上次检查时间」。'

### 2.17 #/logs 运行日志
- pageHead('运行日志', 'N 条记录 · 上限 200 条 · 记录源与订阅的真实界面操作')
- 空：emptyState('还没有运行日志','搜索、播放等操作会记录各源执行情况。','note')
- section '操作记录（N）' → panel > list，logRow：label = 'op · sourceName'；hint（带 log--error / log--warn 类）= '错误|警告|信息 · msg'；右侧 od-nowrap = 'HH:mm:ss'
- section：按钮 '清空日志'(logs-clear)

### 2.18 #/playlists 歌单
- pageHead('全部歌单', 'N 个歌单 · 编辑精选与我自建的歌单', action '新建歌单')
- section '全部歌单' → grid-cards（全部歌单）；空 → emptyState('还没有歌单','点右上角新建一个歌单。','note')

---

## 3. 交互行为

### 3.1 播放引擎（app.js 543–720）
- player = { queue:[], index:-1, playing:false, position:0, context:'', shuffle:load('resonance.shuffle',false), repeat:load('resonance.repeat','all'), pending:'' }
- playQueue(tracks, startIndex, contextLabel)：整表成为队列、index 夹紧、position=0、shuffleHistory=[]、context=标签，随后 beginPlayback(current())
- beginPlayback(track)：清旧定时器；写运行日志 '取播放地址'（msg = '来源返回可用地址：「标题」'）；pending = track.id；playing=false；520ms 后 pending=''、playing=true、pushRecent(current())、同步 UI。等待期间列表行 / 迷你条 / 全屏页都显示 '准备播放中…' 与 spin 蒙层（playerbar 加 .is-pending）
- togglePlay()：无曲目直接返回；若正处于 pending 态 → 立即取消等待并开始播放；否则取反 playing
- jumpTo(index, immediate)：immediate=true（自然播完续播）不进入等待态
- nextIndex(step)：shuffle 时 step<0 走 shuffleHistory 回退（弹到合法索引，历史空则停在当前）；step>0 从「除当前曲目外」的池子随机；非 shuffle 时 i = index + step，越界按 repeat：off → 到头返回 -1（顺序播放停止：playing=false，position=duration），否则回绕到 0 / total-1
- next(auto)：算下一首 → 若记录 shuffleHistory（上限 200）→ jumpTo(i, !!auto)
- prev()：position > 4 秒 → 回到 0 重播；否则上一首（跳转走等待态）
- seekRatio(ratio)：position = clamp(ratio,0,1) * duration
- cycleRepeat()：随机开启时点它 = 退出随机 + repeat='all'；否则 all → one → off → all 轮转，持久化 resonance.repeat，toast 模式名
- setShuffle(on)：持久化；关闭随机时强制 repeat='all' 并清空 shuffleHistory
- pushRecent(track)：去重提到最前，上限 500（RECENT_MAX）
- 播放时钟：window.setInterval(250ms)（TICK=250），playing 时 position += 0.25；到达 duration 时 repeat==='one' → position=0 继续，否则 next(true)
- syncProgress() 每 tick 刷新两个进度条宽度、时间文本、aria-valuenow/valuetext，并调用 updateCurrentRowHighlight() 与 syncLyrics()

### 3.2 点击对象 → 行为
| 点击对象 | data-act | 行为 |
|---|---|---|
| 曲目行主体 | play-track | 已在队列 → jumpTo(该索引)；队列为空(index<0) → playQueue([这首],0,routeLabel() 或 '单曲')；否则插入到当前索引+1 并 jumpTo 它 |
| 专辑卡片播放键 / 专辑页播放 | play-album | playQueue(专辑全部曲目, 0, '专辑') |
| 专辑页随机播放 | shuffle-album | playQueue(tracks, 随机起始, '专辑 · 随机') + setShuffle(true) |
| 歌单卡片播放键 / 歌单页播放 | play-playlist | playQueue(歌单曲目, 0, '歌单') |
| 歌单随机播放 | shuffle-playlist | 随机起始 + '歌单 · 随机' + setShuffle(true) |
| 歌单加入队列 | add-playlist-all | 逐首 enqueue；toast '已加入 N 首到播放队列' 或 '这些歌曲已经在队列里了' |
| 艺人卡片播放键 / 播放热门 | play-artist | playQueue(艺人全部曲目, 0, '艺人') |
| 我喜欢的-播放全部 | play-liked | playQueue(排序后的喜欢列表, 0, '我喜欢的音乐')；空则 toast '还没有喜欢的歌曲' |
| 我喜欢的-随机播放 | shuffle-liked | setShuffle(true) + 随机起始；空同上 |
| 我喜欢的-加入队列 | liked-queue | 逐首 enqueue + toast |
| 排序 chip | liked-sort | 更新 #liked-body，不动整页 |
| 卡片封面/名称 | — | 原生 a[href] 跳 #/album/:id、#/playlist/:id、#/artist/:name |
| 曲目行爱心 / 播放条爱心 / 全屏页爱心 | toggle-like | toggleLike |
| 曲目行更多 | track-menu | openTrackMenu（sheet） |
| 下载按钮 | toggle-download / toggle-track-download | 未下载→startDownload；已下载→二次确认 sheet（'删除缓存'）→ removeCache |

### 3.3 播放控制条（playerbar / 全屏播放页）
- pb-play / np-play → togglePlay()；aria-label 随状态在 '播放' / '暂停' 间切换；data-playing、data-loading 属性表达状态
- pb-prev / np-prev → prev()；pb-next / np-next → next(false)
- pb-shuffle / np-shuffle → toggleShuffle()：toast '随机播放已开启（循环项暂停生效）' / '已关闭随机 · 列表循环'
- pb-repeat / np-repeat → cycleRepeat()：aria-label = 随机中 ? '循环模式：随机播放中，点击回到列表循环' : '循环模式：' + MODE_LABEL[repeat]；aria-pressed = (!shuffle && repeat!=='off')；shuffle 时按钮加 .is-inactive，图标换 i-repeat-one
- 爱心：pb-like / pb-like-c / np-like → toggleLike(current().id)，无曲目时 disabled
- pb-open（封面）/ pb-expand → openNow()（无曲目时 toast '先挑一首歌再展开播放页'）；np-close → closeNow()
- pb-queue / np-queue → openQueue()；pb-downloads → navigate('#/downloads')
- np-lyrics → toggleLyrics()；np-sleep → openSleepSheet()；np-device → openDevices()；np-more → openTrackMenu(current().id)（无曲目 toast '先挑一首歌'）
- pb-mute / np-mute → 静音切换；#pb-volume / #np-volume（range 0–100）→ store.volume
- 进度条 #pb-track / #np-track：click 按 (clientX - rect.left) / rect.width 定位；键盘 ArrowRight +5s、ArrowLeft -5s、Home 0、End 1

### 3.4 弹层（.sheet 通用机制）
openSheet(title, body, opts)：设 #sheet-title / #sheet-body，显示 scrim 与 sheet，强制一次布局后加 .is-open；焦点先给 [data-autofocus] 否则 #sheet-close；注册 Esc/Tab 捕获；closeSheet() 220ms 后隐藏并清空 body，焦点还给 lastFocus；点击 scrim 关闭；Tab 在弹层内循环。

| sheet 标题 | 打开入口 | 条目 / 内容 |
|---|---|---|
| 曲目名 | 行尾更多、全屏页更多 | 立即播放 / 下一首播放 / 加入播放队列 / 喜欢或取消喜欢 / 添加到歌单 / [我的歌单详情内且曲目在列] 从「歌单名」移除(危险) / [有专辑] 查看专辑《专辑名》 / [扫描登记的本地曲目] 从本地库移除(危险) / 下载 或 下载中 N% 或 删除缓存 / 复制分享链接 |
| 歌单名 | 歌单页更多 | 我的歌单：添加歌曲 / 重命名歌单 / 复制分享链接 / 删除歌单(危险)；非我的：收藏到我的歌单 / 复制分享链接 |
| 添加到歌单 | 曲目菜单 | 表单（新建歌单：输入框 + 错误行 + 按钮 '创建并加入《标题》'）+ '已有歌单' 列表（每行 name + 'N 首'，已在其中则 disabled 并显示 i-check） |
| 管理歌曲 · 歌单名 | 添加歌曲 / 歌单菜单 | hint '点一下即可加入或移出，改动会立即保存。' + 全部曲目的 .pick 行（封面 + 标题 + '艺人 · 专辑' + i-check/i-plus），aria-pressed 表示是否在内 |
| 新建歌单 | 首页空态 / 全部歌单页 | 表单 #new-playlist-form：'歌单名称' 输入（maxlength 24，placeholder '例如：周末早晨'，data-autofocus）+ 错误 '请输入歌单名称' + 提交 '创建歌单' |
| 重命名歌单 | 歌单菜单 / 工具行 | 表单 #rename-playlist-form：名称（maxlength 24）+ 简介（maxlength 48，hint '一句话说明这个歌单，会显示在歌单头部。'）+ '保存' |
| 删除歌单 | 工具行/菜单 | 二次确认（openConfirm）：文案 '删除后无法恢复，「名称」里的歌曲仍保留在音乐库中。' + '取消' / '删除歌单' |
| 删除缓存 | 已下载按钮 / 曲目菜单 | 专辑：'删除「标题」的缓存后需要重新下载才能离线使用（原型不产生真实文件）。'；单曲：'删除「标题」的缓存后需要重新下载（原型不产生真实文件）。' + '删除缓存' |
| 播放队列 | pb-queue / np-queue | 见 3.5 |
| 睡眠定时器 | np-sleep | 见 3.6 |
| 选择播放设备 | np-device | 见 3.7 |
| 关于这个原型 | 我的-关于-说明 | 5 段说明（响应式同套界面 / 封面与信息为真实作品但无音频 / 歌词来源说明 / 播放模式与睡眠与下载口径 / 数据存在本地存储）+ '知道了' |
| 扫描本地文件夹 | 本地音乐-扫描文件夹 / 文件夹页重新扫描 | hint ×2（扫描说明、歌词需同批选中）+ 隐藏 file input#scan-input[webkitdirectory][accept='audio/*,.mp3,.m4a,.flac,.wav,.ogg,.opus,.aac,.lrc,text/plain'] + '选择文件夹' + #scan-status 状态区 |
| 添加订阅 | 音乐源/订阅页 | 表单 #sub-add-form：订阅地址（必填，placeholder 'https://example.com/rule.json'）/ 类型下拉（规则 · 展开 1 个源 / 规则订阅组 · 展开 3 个源 / MusicFree 订阅组 · 展开 2 个源 / 单插件 · 展开 1 个源）/ 别名（可选，placeholder '例如：我的规则集'，maxlength 24）+ '添加订阅' + 演示模式说明 |
| 订阅标题（别名或类型名） | 订阅行更多 | 只读信息行：订阅地址 / 类型 / 别名（未设置）/ 上次检查 / 展开源数量 + '删除订阅' |
| 删除订阅？ | 订阅详情 | '删除订阅会注销它展开的 N 个源，并从源列表中移除。此操作不可撤销。' + '确认删除' / '取消' |
| 源名 | 音乐源行更多 | 只读：源 ID / 类型（+ 演示展开）/ 来源归属 / 添加时间（内置演示源）；种子源显示 '内置演示源不可删除，需要时把它停用即可。'，非种子源显示 '移除这个源' |
| 导入插件文件 | 音乐源页 | 说明（.js/.json/.lx/.mf/.txt，以文件名注册为演示源）+ 隐藏 input#source-file + '选择插件文件' + '文件只在本地读取文件名，不会被上传，也不会被执行。' |

### 3.5 播放队列 sheet
- 空队列：emptyState('播放队列是空的','播放任意歌曲后，队列会显示在这里。','queue')
- 非空：
  - 头行：field__hint 'N 首 · {随机播放 | MODE_LABEL[repeat]}' + button.btn--outline '清空队列'
  - 说明：'拖动左侧把手调整顺序，向左滑动可移除（2 秒内可撤销）。队列不持久化，重启后为空。'
  - 行：div.track.track--art.track--queue[data-id][data-qi] = 把手 span.track__grip（三横线）+ button.track__hit（data-act=queue-jump，封面带状态蒙层，标题 + 艺人）+ track__dur + track__actions（当前行 span.badge.badge--accent '播放中' + 移除按钮 data-act=queue-remove[aria-label='从队列移除：标题'][当前行 disabled]）
  - 打开后把当前行 scrollIntoView({block:'nearest'})
- 拖拽排序：把手 pointerdown → setPointerCapture，pointermove 中按 clientY 命中其它行即 insertBefore 重排并重编号 data-qi；pointerup 时调用 moveInQueue(from,to) 并整体重绘重绑
- 滑动删除：行 pointerdown（排除 grip 与 actions 区域）→ 判定位移超过 12px 且以水平左滑为主才接管；位移上限 -96px；松手 <= -56px 即移除
- 删除当前播放曲目被拒绝：removeFromQueue 返回 null → toast '正在播放的这首歌不能从队列移除'
- 撤销：toastUndo 生成带「撤销」按钮的 toast（2000ms），offerQueueUndo 记录 {track,index,timer}；撤销后 splice 回原位（插入点 <= 当前索引时 index+1），重开队列并 toast '已恢复「标题」'
- 清空队列：保留正在播放的一首，index=0；toast '已清空队列（保留正在播放的这首）' / '队列已清空'
- 队列去重：enqueue 按 id 去重；addToQueue 命中已存在 → toast '队列里已经有「标题」'
- 下一首播放：playNextUp 已存在时先 splice 再插到 index+1；toast '已设为下一首播放'

### 3.6 睡眠定时器
- 选项 15 / 30 / 60 / 90 分钟（sleep-grid 两列按钮，文案 'N 分钟'）
- 未激活：hint '设定一段时间后自动暂停播放。睡眠定时器不会在重启后保留。' + field__label '暂停时间'
- 激活中：'剩余时间' + #sleep-left（m:ss）+ hint '到点后自动暂停播放；重新设定会覆盖当前倒计时。' + '取消定时器' + field__label '重新设定'
- 每秒递减；到 0 → 清空、playing=false、同步 UI、toast '睡眠定时器已到时，播放已暂停'
- toast：'已设定 N 分钟后暂停播放' / '已取消睡眠定时器'
- 沉浸页上下文行（#np-source）在激活时追加 '睡眠 m:ss'；不持久化

### 3.7 播放设备
- DEVICE_OPTIONS = [{ name:'本机扬声器', hint:'这台设备' }, { name:'客厅音箱', hint:'Wi-Fi · 上次连接 2 天前' }, { name:'Bose QC45', hint:'蓝牙' }]
- sheet '选择播放设备'：每行 action-row[data-act=pick-device][aria-pressed]，名称 + small hint（当前设备时显示 '当前设备'），选中行右侧 i-check
- 点击 → store.device 持久化 + toast '已切换到「名称」' + 重开 sheet

### 3.8 歌词视图
- 入口：np-lyrics（aria-label '歌词' / '收起歌词'，aria-pressed）。无曲目时 toast '先挑一首歌'，不展开
- 打开状态存 resonance.lyricsOpen；歌词与封面共用同一个正方形舞台（.np__art--lyrics），只换内容不改尺寸，切换不产生页面位移
- 顶部注释行 #np-lyrics-note：LRC 来源 → '来自同名 .lrc 文件'；演示歌词 → '示例歌词 · 非原曲文本'；无歌词 → 隐藏
- 有歌词：ol.ly 内 li.ly__line（段落间隔为 li.ly__line--gap[aria-hidden]，空文本不参与高亮）
- 无歌词空状态：'这首歌的来源没有提供歌词' + 文案（本地曲目：'扫描时把与音频同名的 .lrc 文件一起选中，就能显示歌词（浏览器不允许按路径二次读取文件）。'；在线曲目：'该来源没有返回歌词内容，换一首试试。'）
- 刷新时机：曲目变化或 force 时重建列表（scrollTop=0）；每 250ms tick 只在「活动行变化」时改 DOM
- 手动滚动（wheel / touchstart / pointerdown / keydown，passive）→ 暂停跟随；4 秒后恢复跟随并把当前行重新居中
- prefers-reduced-motion: reduce 时滚动改为瞬时（scrollTop 直赋值）

### 3.9 收藏（喜欢）
toggleLike(id)：切换 store.liked（Set）→ 持久化 resonance.liked（数组）→ toast '已加入「我喜欢的音乐」'(icon heart-fill) / '已从「我喜欢的音乐」移除'(icon heart) → syncPlayer()；若当前在 liked 或 library 页则整页 render()，否则 refreshLikeButtons() 只更新 .track__heart 的 aria-pressed / aria-label / 图标。

### 3.10 主题
toggleTheme()：切换 store.theme('dark'|'light') → html[data-theme] → 持久化 resonance.theme → 两个切换键的图标在 #i-sun / #i-moon 间换（深色时显示太阳图标）→ #theme-toggle-side-label 文案 '切换到浅色' / '切换到深色' → meta[name=theme-color] 在 '#0C0E11' / '#F6F7F9' 间换 → 我的页 switch 的 aria-checked 同步。

### 3.11 音量与静音
- store.volume 0.0–1.0，界面 range 0–100；input 事件写 store.volume = value/100，>0 时记 lastVolume，muted = (volume===0)，持久化 resonance.volume，并同步 --vol CSS 变量（滑块填充）
- 静音键：muted = store.volume > 0；store.volume = muted ? 0 : (lastVolume || 0.8)；toast '已静音' / '音量 N%'
- 图标在 i-volume / i-volume-mute 间切换；aria-pressed 标记静音
- 手机端：沉浸页音量组（.np__volume）在 ≤767 隐藏；播放条音量在 768–1180 隐藏（平板交给系统音量）；≥1181 才恢复

### 3.12 本地扫描
- 选择文件夹（webkitdirectory）→ 分离 .lrc 与音频（AUDIO_EXT 匹配 mp3/m4a/m4b/aac/flac/wav/wave/ogg/oga/opus/wma/aiff/aif/alac/ape，或 MIME audio/*）
- .lrc 用 FileReader 读取并按「去扩展名小写文件名」建索引 lrcBatch，全部读完后 applyLrcToScanned() 把同名歌词挂到已登记的本地曲目（store.lyrics[id] = { lines }），toast '已为 N 首本地曲目匹配同名 .lrc 歌词'
- 音频用 Audio 元数据探测时长（6 秒超时、error 视为跳过）；读不到就如实跳过，不编造时长
- 状态区文案：'正在读取 N / M 个音频文件…'；'这个文件夹里没有可识别的音频文件，只读到了 N 个 .lrc 歌词文件。'；'这个文件夹里没有可识别的音频文件。'；'已登记 N 个本地文件。'；'没有新增文件：这些文件重复或无法读取时长。'；'另有 N 个文件已跳过：a、b 等'
- 登记 id = 'local-' + hashStr(文件名 + '|' + 取整时长)；条目 { id, title(去扩展名), artist:'本地文件', duration, folder }，folder 取 webkitRelativePath 的目录部分，否则 '本地音乐'
- 移除本地曲目：从 store.scanned / TRACKS / TRACK_BY_ID / 喜欢集合 / 播放队列中清除，toast '已从本地库移除「标题」'

### 3.13 下载任务
- startDownload(kind, id)：已在下载 → toast '这个任务正在下载中'；否则建 { key:'kind:id', kind, id, title, sub, cover, pct:0, state:'downloading', handle } 并 unshift，toast '开始下载「标题」'
  - sub：专辑 = '艺人 · 专辑 · N 首'；单曲 = '艺人 · 单曲'
- runDownload：每 420ms pct += 6 + random(0..8)，到 100 → finishDownload
- finishDownload：state='done'；专辑则整张（含曲目）标记 downloaded；单曲标记该曲目；toast '「标题」已下载完成'；若在下载页 → 刷新 #dl-body；若正停在对应专辑页 → render()
- cancelDownload → state='cancelled' + toast '已取消「标题」的下载'；retryDownload → 重跑 + toast '重新开始下载「标题」'；removeCache → 清缓存标记并删掉任务记录 + toast '已删除「标题」的缓存'（无记录时 '已删除缓存'）；clearFinishedDownloads → 只留下载中的，toast '已清理 N 条记录' / '没有可清理的记录'
- downloads 数组不持久化（刷新即空）

### 3.14 源 / 订阅 / 日志
- toggleSource：切换 enabled → saveSources → 写日志（'启用源'/'停用源'）→ render → toast '「名称」已启用/已停用'
- 添加订阅：URL 校验必须 http/https，非法 → toast '请输入有效的订阅地址（http / https）'；重复 → toast '该地址已存在'；否则按 SUB_TYPES 的 expand 数展开出演示源（id = 订阅id + '-' + i，name = 别名或类型名 + ' ' + i，plugin/mf-group 展开成插件类型，其余规则类型），toast '订阅添加成功（演示展开 N 个源）'
- checkSub / checkAllSubs：只更新 lastCheckAt 与日志，toast '更新完成（演示模式：未联网，已更新时间）' / '已更新 N 条（演示模式：未联网）'
- 删除订阅：二次确认 → 注销展开出的全部源 + 移除订阅 + toast '订阅已删除'
- 导入插件文件：读文本；.json 有 name 字段则用 name，否则用文件名（解析失败写 warning 日志）→ 注册 { id:'imp-'+时间戳36进制, type:'plugin', origin:'import', enabled:true } → toast '已导入源「名称」（演示模式，未解析执行）'
- 日志：LOG_MAX=200，logAdd(op, sourceId, ok, msg, level) 结构 { t, level, op, sourceId, sourceName, ms:0, ok, msg }；sourceId 为 'app' 时 sourceName='应用'

### 3.15 全局交互与快捷键
- 所有 [data-act] 走一个 document click 委托（e.target.closest('[data-act]')），disabled 元素忽略；scrim 点击关闭弹层
- change 委托：仅 #scan-input（handleScanFiles）
- input 委托：#search-input → 实时搜索（不整页重绘，避免丢焦点）
- keydown 委托：Enter 在 #search-input → 记录最近搜索（去重、最多 8 条）
- 全局快捷键（非输入框、非按钮/链接、无 meta/ctrl/alt 时）：Space → 播放/暂停；Shift+ArrowRight → 下一首；Shift+ArrowLeft → 上一首；m / M → 触发静音键
- submit 委托：#new-playlist-form（空名显示 '请输入歌单名称' 并聚焦）、#rename-playlist-form（空名显示 '请输入歌单名称'）
- hashchange → onRoute()；首次加载 init()：applyTheme → bind → renderSidebarPlaylists → onRoute → syncPlayer(true)；若当前无曲目，用真实数据兜底：queue = dark-side-of-the-moon 全部曲目，index = 3（Dark Side of the Moon #4 = 'Time'），playing=false，context='专辑'
- 图片 error 捕获（capture）→ 置 img.style.visibility='hidden' 防破图

---

## 4. 数据模型

### 4.1 内置专辑 ALBUM_DATA（原文前 3 条）
- { id:'abbey-road', title:'Abbey Road', artist:'The Beatles', year:1969, genre:'摇滚', tracks:['Come Together','Something',"Maxwell's Silver Hammer","Oh! Darling","Octopus's Garden",'I Want You (She’s So Heavy)','Here Comes the Sun','Because','You Never Give Me Your Money','Sun King','Mean Mr. Mustard','Polythene Pam','She Came in Through the Bathroom Window','Golden Slumbers','Carry That Weight','The End','Her Majesty'] }
- { id:'random-access-memories', title:'Random Access Memories', artist:'Daft Punk', year:2013, genre:'电子', tracks:['Give Life Back to Music','The Game of Love','Giorgio by Moroder','Within','Instant Crush','Lose Yourself to Dance','Touch','Get Lucky','Beyond','Motherhood','Fragments of Time',"Doin' It Right",'Contact'] }
- { id:'blonde', title:'Blonde', artist:'Frank Ocean', year:2016, genre:'R&B', tracks:['Nikes','Ivy','Pink + White','Be Yourself','Solo','Skyline To','Self Control','Good Guy','Nights','Solo (Reprise)','Pretty Sweet','Facebook Story','Close to You','White Ferrari','Seigfried','Godspeed','Futura Free'] }
- 其余 13 张 id：kind-of-blue / ok-computer / midnights / when-we-all-fall-asleep / dark-side-of-the-moon / damn / rumours / nevermind / thriller / back-to-black / future-nostalgia / a-night-at-the-opera / blue

### 4.2 派生对象
- ALBUMS[i] = { id, title, artist, year, genre, cover: 'assets/covers/' + id + '.jpg', imported, downloaded, tracks:[Track] }
- Track = { id: 'albumId#序号(1 起)', no, title, artist, albumId, album(专辑名), cover(同专辑封面), genre, duration, local, downloaded, src }
  - duration = makeDuration(id) = 148 + (hashStr(id) * 37) % 214（约 149–361 秒；hashStr 为 h = h*31 + charCode 累加后取绝对值）
  - local = 专辑在 IMPORTED_ALBUMS 内，或曲目 id 在 IMPORTED_EXTRA 内
  - src = SOURCE_BY_TRACK[id] || SOURCE_BY_ALBUM[albumId] || 'local'
- 扫描登记的本地曲目（scannedToTrack）= { id, no:0, title, artist: e.artist || '本地文件', albumId:'', album:'本地音乐', cover:'', genre:'本地', duration, local:true, downloaded:false, scanned:true, folder, src:'local' }
- Artist = { name, albums:[Album], tracks:[Track] }，按 name.localeCompare 升序
- 歌单 Playlist = { id, name, desc, colors:[色1,色2], refs:['专辑id#序号', ...], user?:true }
- 自建歌单默认（store.userPlaylists 初值）：{ id:'up-commute', name:'通勤路上', desc:'单程刚好听完', colors:['#3B4C9E','#14171C'], refs:['midnights#3','future-nostalgia#2','abbey-road#7','rumours#5','nevermind#2'], user:true }
- 配表：
  - IMPORTED_ALBUMS = ['kind-of-blue','blue','a-night-at-the-opera']；IMPORTED_EXTRA = ['nevermind#11','rumours#7']
  - DOWNLOADED_ALBUMS = ['midnights','future-nostalgia','abbey-road']
  - SEED_LIKED = ['abbey-road#7','blonde#7','dark-side-of-the-moon#4','kind-of-blue#1']
  - SEED_RECENT = ['midnights#3','future-nostalgia#2','ok-computer#2','rumours#3','back-to-black#5']
  - SEED_RECOMMEND = ['midnights#3','future-nostalgia#2','ok-computer#2','blonde#7','back-to-black#5','rumours#3','kind-of-blue#1','dark-side-of-the-moon#4']
  - SOURCE_SEED = [{ id:'fy', name:'枫叶', type:'rule' }, { id:'aiting', name:'爱听', type:'rule' }, { id:'yu7', name:'Yu7', type:'plugin' }]
  - SOURCE_TYPES = { local:'本地', rule:'规则', plugin:'插件' }
  - SUB_TYPES = [{ id:'rule', label:'规则', expand:1, hint:'该地址是一个规则 JSON' }, { id:'ruleset', label:'规则订阅组', expand:3, hint:'该地址是规则数组（或带 rules 字段的对象）' }, { id:'mf-group', label:'MusicFree 订阅组', expand:2, hint:'该地址是插件名 + 地址的索引' }, { id:'plugin', label:'单插件', expand:1, hint:'该地址是一个插件文件内容' }]
  - SOURCE_BY_ALBUM：midnights/future-nostalgia/when-we-all-fall-asleep/random-access-memories/abbey-road/damn → fy；ok-computer/blonde/kind-of-blue/nevermind/blue → aiting；back-to-black/rumours/dark-side-of-the-moon/thriller/a-night-at-the-opera → yu7
  - SOURCE_BY_TRACK = { 'midnights#3':'fy', 'blonde#7':'aiting', 'rumours#3':'yu7' }
  - SOURCE_PLAYLISTS = { fy:['pl-today','pl-night-drive'], aiting:['pl-focus','pl-jazz'], yu7:['pl-rock-90s','pl-morning'] }
  - PALETTE = { '摇滚':'#B4452B', '流行':'#C0467D', '爵士':'#1F6C7A', '电子':'#3B4C9E', '嘻哈':'#8A5A16', 'R&B':'#7A3A63', '民谣':'#4C6B3A', '灵魂乐':'#A2451F' }
  - CATEGORIES（浏览分类，顺序）：流行 #C0467D / 摇滚 #B4452B / 爵士 #1F6C7A / 电子 #3B4C9E / 嘻哈 #8A5A16 / R&B #7A3A63 / 民谣 #4C6B3A / 灵魂乐 #A2451F
  - PLAYLIST_DATA 6 个：pl-night-drive 深夜公路（低速巡航与霓虹灯影，refs 8 首）/ pl-focus 专注工作（不抢注意力的长线条，8 首）/ pl-morning 清晨唤醒（把窗帘拉开的那一下，7 首）/ pl-rock-90s 九十年代摇滚（失真、贝斯线与嘶吼，7 首）/ pl-jazz 爵士夜（一杯不加冰的威士忌，8 首）/ pl-today 今日推荐（按你的收听习惯生成，8 首）；colors 各为两个十六进制色值
  - 运行期常量：RECENT_MAX = 500、LOG_MAX = 200、TICK = 250（ms）、MODE_LABEL = { all:'列表循环', one:'单曲循环', off:'顺序播放' }、DL_STATE（见 2.14）、LIKED_SORTS = [{recent:'最近喜欢'},{title:'标题'},{duration:'时长'}]

### 4.3 歌词数据结构
- 演示歌词 LYRIC_DATA：对象，key = 曲目 id，value = 字符串数组（空串表示段落间隔，不参与高亮）。收录 9 首：midnights#3、future-nostalgia#2、ok-computer#2、back-to-black#5、rumours#3、abbey-road#7、blonde#7、dark-side-of-the-moon#4、blue#8。示例（midnights#3 前 3 行原文）：'深夜三点我还醒着' / '把心事翻来覆去地读' / '我数着自己所有的错'
- LRC（store.lyrics）：{ 曲目id: { lines: [[秒(小数), 文本], ...] } }，秒 = 分*60 + 秒 + 毫秒/1000（3 位）或 百分秒/100（2 位）
- 时间轴不写入数据，而是运行时按曲目时长均分生成（见第 5 节）

### 4.4 封面文件与曲目映射
assets/covers/ 下 16 个 jpg，文件名 = 专辑 id，专辑全部曲目共用同一封面：
| 封面文件 | 专辑 | 艺人 | 流派 | 曲目数 |
|---|---|---|---|---|
| abbey-road.jpg | Abbey Road | The Beatles | 摇滚 | 17 |
| random-access-memories.jpg | Random Access Memories | Daft Punk | 电子 | 13 |
| blonde.jpg | Blonde | Frank Ocean | R&B | 17 |
| kind-of-blue.jpg | Kind of Blue | Miles Davis | 爵士 | 5 |
| ok-computer.jpg | OK Computer | Radiohead | 摇滚 | 12 |
| midnights.jpg | Midnights | Taylor Swift | 流行 | 13 |
| when-we-all-fall-asleep.jpg | When We All Fall Asleep, Where Do We Go? | Billie Eilish | 流行 | 14 |
| dark-side-of-the-moon.jpg | The Dark Side of the Moon | Pink Floyd | 摇滚 | 10 |
| damn.jpg | DAMN. | Kendrick Lamar | 嘻哈 | 14 |
| rumours.jpg | Rumours | Fleetwood Mac | 摇滚 | 11 |
| nevermind.jpg | Nevermind | Nirvana | 摇滚 | 12 |
| thriller.jpg | Thriller | Michael Jackson | 流行 | 9 |
| back-to-black.jpg | Back to Black | Amy Winehouse | 灵魂乐 | 10 |
| future-nostalgia.jpg | Future Nostalgia | Dua Lipa | 流行 | 11 |
| a-night-at-the-opera.jpg | A Night at the Opera | Queen | 摇滚 | 12 |
| blue.jpg | Blue | Joni Mitchell | 民谣 | 10 |
- 映射规则：cover = 'assets/covers/' + albumId + '.jpg'；扫描登记曲目 cover = '' → 用 span.track__cover--empty + i-note 占位（无破图）
- 图片统一 width=600 height=600、loading=lazy、decoding=async；失败时全局 error 捕获隐藏 img

---

## 5. 歌词逐行高亮与滚动算法（伪代码 / Dart 风格）

1) 选源：本地扫描曲目优先同批选中的同名 .lrc，其次内置演示歌词，都没有则空状态

    String lyricSource(Track t) {
      final lrc = store.lyrics[t.id];
      if (lrc != null && lrc.lines.isNotEmpty) return 'lrc';
      if (LYRIC_DATA[t.id]?.isNotEmpty == true) return 'demo';
      return '';
    }

2) 转成统一条目 { text, at }；at == null 表示段落间隔（不参与高亮）

    List<LyricEntry>? lyricEntries(Track t) {
      final src = lyricSource(t);
      if (src == 'lrc') {
        return store.lyrics[t.id]!.lines.map((row) => row[1].isNotEmpty
            ? LyricEntry(text: row[1], at: row[0])
            : LyricEntry(text: '', at: null)).toList();
      }
      if (src != 'demo') return null;
      final raw = LYRIC_DATA[t.id]!;
      final timed = raw.where((l) => l.isNotEmpty).length;   // 只数非空行
      const lead = 5.0;                                      // 前奏留白 5s
      final span = max(24.0, t.duration - lead - 6.0);        // 至少 24s
      final step = span / max(1, timed);                      // 均分
      var k = 0;
      return raw.map((line) {
        if (line.isEmpty) return LyricEntry(text: '', at: null);  // 段落间隔
        final e = LyricEntry(text: line, at: lead + step * k);
        k++;                                                   // 只有非空行推进计数
        return e;
      }).toList();
    }

3) 每个播放 tick（250ms）刷新高亮：线性扫描取最后一个 at <= pos

    void updateLyrics() {
      if (!lyricsOpen || current == null) return;
      final t = current!;
      final entries = lyricEntries(t);
      final pos = min(player.position, t.duration);
      var active = -1;
      if (entries != null) {
        for (var i = 0; i < entries.length; i++) {
          final at = entries[i].at;
          if (at != null && pos >= at) active = i;   // 不 break，最后一个命中即当前行
        }
      }
      if (active == lyricsActive) return;            // 行没变则不碰 DOM（时钟每秒跑 4 次）
      final prev = lyricsActive;
      lyricsActive = active;
      if (prev >= 0) lines[prev].removeClass('is-active');
      if (active >= 0) {
        lines[active].addClass('is-active');
        if (lyricsFollow) scrollLyricsTo(lines[active]);   // 居中跟随
      }
    }

4) 居中滚动：目标行中心对齐可视区中心，再夹紧到可滚范围

    void scrollLyricsTo(Widget line) {
      final box = lyricsScrollBox;
      if (box == null || box.clientHeight == 0) return;
      final maxTop = max(0.0, box.scrollHeight - box.clientHeight);
      var top = line.offsetTop - (box.clientHeight - line.offsetHeight) / 2;
      top = top.clamp(0.0, maxTop);
      if (prefersReducedMotion) box.scrollTop = top;     // 减少动效 → 瞬时
      else box.animateTo(top, duration: 300.ms);         // 原生 scrollTo({behavior:'smooth'})
    }

5) 手动滚动接管：停手 4 秒后交还播放进度

    void onLyricsScrollInput() {
      lyricsFollow = false;
      lyricsFollowTimer?.cancel();
      lyricsFollowTimer = Timer(4.seconds, () {
        lyricsFollow = true;
        if (lyricsActive >= 0) scrollLyricsTo(lines[lyricsActive]);  // 重新居中当前行
      });
    }

6) 曲目切换 / 展开播放页：重建列表并复位

    void syncLyrics({bool force = false}) {
      final on = lyricsOpen && current != null;      // 无曲目时不占舞台
      final key = on.toString() + '|' + (current?.id ?? '');
      if (force) { lyricsRenderedFor = ''; lyricsActive = -1; lyricsFollow = true; }
      if (force || key != lyricsUiState) {
        lyricsUiState = key;
        btn.ariaPressed = on; btn.ariaLabel = on ? '收起歌词' : '歌词';
        art.toggleClass('np__art--lyrics', on);
        view.hidden = !on;
      }
      if (!on) return;
      if (lyricsRenderedFor != current!.id) {
        lyricsRenderedFor = current!.id; lyricsActive = -1;
        final entries = lyricEntries(current!);
        list.innerHTML = entries?.map(lyricLineHtml).join('') ?? '';
        list.hidden = entries == null;
        empty.hidden = entries != null;
        note.textContent = lsrc == 'lrc' ? '来自同名 .lrc 文件'
                         : (lsrc == 'demo' ? '示例歌词 · 非原曲文本' : '');
        scrollTop = 0;
      }
      updateLyrics();
    }

7) LRC 解析：一行多时间戳可展开；不认识的标签行忽略；最多 400 行

    List<List<num>> parseLrc(String text) {
      final out = <List<num>>[];
      for (final line in text.replaceAll('\r', '').split('\n')) {
        final stamps = RegExp(r'\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]').allMatches(line);
        if (stamps.isEmpty) continue;
        final body = line.replaceAll(RegExp(r'\[[^\]]*\]'), '').trim();
        for (final st in stamps) {
          final m = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]').firstMatch(st.group(0)!);
          if (m == null) continue;
          final frac = m[3] == null ? 0.0 : int.parse(m[3]!) / (m[3]!.length == 3 ? 1000 : 100);
          out.add([int.parse(m[1]!) * 60 + int.parse(m[2]!) + frac, body]);
        }
      }
      out.sort((a, b) => a[0].compareTo(b[0]));
      return out.take(400).toList();
    }

8) 行 HTML：空文本 → 段落间隔节点（aria-hidden）

    String lyricLineHtml(Entry e) => e.text.isEmpty
        ? '<li class="ly__line ly__line--gap" aria-hidden="true"></li>'
        : '<li class="ly__line">' + esc(e.text) + '</li>';

视觉：.ly__line 默认 --text-mute；.ly__line.is-active 变 --accent、左侧 2px 强调边框、translateX(2px)；滚动容器上下有 20px 渐隐遮罩。

---

## 6. 状态管理

### 6.1 全局状态对象
    store = {
      liked: Set<string>,          // 喜欢（数组持久化）
      recent: string[],            // 最近播放 id，去重、上限 500
      searches: string[],          // 最近搜索词，上限 8
      userPlaylists: Playlist[],   // 自建歌单
      volume: number,              // 0.0–1.0
      theme: 'dark' | 'light',
      lyricsOpen: boolean,
      lyrics: { [trackId]: { lines: [[sec, text]] } },
      wifiOnly: boolean,
      device: string,
      scanned: [{ id, title, artist, duration, folder }]
    }
    player = { queue, index, playing, position, context, shuffle, repeat: 'all'|'one'|'off', pending }
    muted（由 store.volume === 0 推导）、lastVolume（取消静音恢复值）
    sourceStore: { id, name, type, origin, enabled, addedAt, demo?, demoFile? }
    subs: { id, url, type, alias, addedAt, lastCheckAt, sourceIds }
    logs: { t, level:'info'|'warning'|'error', op, sourceId, sourceName, ms, ok, msg }
    downloads: { key, kind:'album'|'track', id, title, sub, cover, pct, state, handle }（不持久化）
    sleep = { left:int 秒, handle, minutes }
    页面态：route{name,param}、navTrail[]、searchQuery、searchSrc('all'|'local'|源id)、searchMore、
            libraryTab('all'|'src:<id>'|'downloaded')、likedSort、highlightState、shuffleHistory[]、
            queueUndo{track,index,timer}、lyrics{Open/Follow/Active/RenderedFor}、
            pendingPlaylistTrack、pendingPlaylistId、playlistCache、sheet{el,scrim,lastFocus,onClose}
注意：libraryTab 初值 'songs'，但分栏只含 all / src:* / downloaded，renderLibrary 首行会把失效值重置为 'all'。

### 6.2 localStorage（key → 内容 → 默认值）
| key | 内容 | 默认值 |
|---|---|---|
| resonance.liked | 喜欢曲目 id 数组 | SEED_LIKED（4 首） |
| resonance.recent | 最近播放 id 数组（≤500） | SEED_RECENT（5 首） |
| resonance.searches | 搜索词数组（≤8） | [] |
| resonance.userPlaylists | 自建歌单数组 | 1 个（通勤路上） |
| resonance.volume | 0–1 数值 | 0.8 |
| resonance.theme | 'dark' / 'light' | 'dark' |
| resonance.lyricsOpen | 布尔 | false |
| resonance.lyrics | { 曲目id: { lines: [[sec,text]] } } | {} |
| resonance.wifiOnly | 布尔 | true |
| resonance.device | 设备名 | '本机扬声器' |
| resonance.scanned | 扫描登记条目数组 | [] |
| resonance.shuffle | 布尔 | false |
| resonance.repeat | 'all' / 'one' / 'off' | 'all' |
| resonance.sources | 源记录数组（含订阅展开与导入的） | [] |
| resonance.subs | 订阅数组 | [] |
| resonance.logs | 日志数组（≤200） | [] |

load/save 用 try/catch 包裹（隐私模式/无存储时不报错）。

---

## 7. 移动端 vs 桌面端

**判断方式**：app.js 中没有任何基于窗口宽度的 JS 分支（唯一的 matchMedia 是 prefers-reduced-motion: reduce）；布局切换全部由 CSS 媒体查询完成，JS 只做两件事：① 按 ROOT_WIDE / ROOT_MOBILE 常量切换三个返回键的 hidden；② render() 里 document.body.classList.toggle('is-sub', !ROOT_MOBILE.includes(name))，手机上二级页隐藏 tabbar。所有 DOM（sidebar / topbar / tabbar / playerbar / nowplaying）始终存在，只靠 CSS 显示隐藏。

| 断点 | 布局与行为 |
|---|---|
| ≤767 手机 | .sidebar 隐藏；.topbar 显示（返回键载体 = #topbar-back）；.tabbar 显示（body.is-sub 时隐藏）；播放条只剩 [封面+歌名+艺人+爱心] + [上一/播放/下一]，顶部 2px 迷你进度线 .pb__progress-mini；.pb__opt（随机/循环）、.progress--bar、.pb__tools 全部隐藏；沉浸页隐藏 .np__volume，.np__tools 居中（gap 24px）；.page__head 变两行、.hero 居中、.search-sticky 吸顶；.track__src max-width 38%、.track__meta .badge 隐藏；--gutter:16px |
| 768–1023 平板（窄） | .sidebar 显示为 88px 图标轨（--rail-w:88px，隐藏文字标签/你的歌单分组/品牌文字/底部按钮文字）；.topbar 隐藏；.tabbar 隐藏；返回键载体 = #float-back（fixed，left: calc(88px + 16px)，top:16px；.view 上边距让出 44px 高度）；播放条三区一行（flex，不换行） |
| 768–1180 平板（含 iPad 横屏 1024/1080/1180） | .pb__meta 隐藏、.pb__now 只留封面（flex:none）、第一区爱心隐藏、.pb__like--ctrl（控件行首个）显示、#pb-mute 与 #pb-volume 整组隐藏（交给系统音量）、.pb__now-c 显示（歌名/艺人在控件行左侧，吃掉余量让按钮组靠右） |
| ≥1024 桌面 | --sidebar-w:264px 完整侧边栏（图标+文字+「你的歌单」+主题按钮）；返回键载体 = #brand-back（品牌行右侧）；顶栏隐藏；.np__body 变两列（封面/歌词 ｜ 信息面板）；.sheet 变居中模态（min(560px,92vw)，max-height 80vh，圆角 --r-xl，.sheet__grab 隐藏）；.cat-grid 4 列；--gutter:32px |
| ≥1440 | --gutter:40px、--content-max:1280px；卡片加宽（.card 188px / .card--wide 258px） |
| prefers-reduced-motion: reduce | 所有动画/过渡压到 0.001ms；歌词滚动改瞬时 |

其它令牌：--sidebar-w:264px、--rail-w:88px、--player-min:64px、--tabs-h:60px、--content-max:1240px（≥1440 覆盖为 1280px）；曲目行 grid 固定 minmax(0,1fr) auto auto，.track__hit 内列宽 28px（无封面）/42px（有封面）；卡片网格 repeat(auto-fill,minmax(148px,1fr))；cat-grid 2/3/4 列；stats 3 列；睡眠选项 2 列。

---

## 8. 细节清单（文案逐字保留）

### 8.1 Toast 文案（全部；图标仅两种：#i-info 用于 kind==='info'，其余一律 #i-check）
| 触发 | 文案 |
|---|---|
| 加入喜欢 / 取消喜欢 | 已加入「我喜欢的音乐」 / 已从「我喜欢的音乐」移除 |
| 队列重复 | 队列里已经有「标题」 |
| 加入队列 / 下一首播放 | 已加入播放队列 / 已设为下一首播放 |
| 批量加入队列 | 已加入 N 首到播放队列 / 这些歌曲已经在队列里了 |
| 清空队列 | 已清空队列（保留正在播放的这首） / 队列已清空 |
| 移除队列被拒 | 正在播放的这首歌不能从队列移除 |
| 撤销 toast / 撤销成功 | 已从队列移除「标题」（按钮「撤销」，2 秒） / 已恢复「标题」 |
| 睡眠 | 已设定 N 分钟后暂停播放 / 已取消睡眠定时器 / 睡眠定时器已到时，播放已暂停 |
| 随机 | 随机播放已开启（循环项暂停生效） / 已关闭随机 · 列表循环 |
| 循环 | 列表循环 / 单曲循环 / 顺序播放；随机中切换：已退出随机 · 列表循环 |
| 音量 | 已静音 / 音量 N% |
| 下载 | 开始下载「标题」 / 「标题」已下载完成 / 已取消「标题」的下载 / 重新开始下载「标题」 / 已删除「标题」的缓存 / 已删除缓存 / 已清理 N 条记录 / 没有可清理的记录 / 这个任务正在下载中 |
| 复制链接 | 链接已复制 / 歌单链接已复制 / 复制失败，请手动复制地址栏 / 浏览器不支持自动复制 |
| 歌单 | 已加入「歌单名」 / 已从「歌单名」移除 / 已创建歌单「名称」 / 歌单已更新 / 已删除「名称」 / 已收藏到我的歌单 |
| 搜索历史 | 已清空搜索历史 |
| 源与订阅 | 「名称」已启用 / 「名称」已停用 / 请输入有效的订阅地址（http / https） / 该地址已存在 / 订阅添加成功（演示展开 N 个源） / 更新完成（演示模式：未联网，已更新时间） / 已更新 N 条（演示模式：未联网） / 还没有订阅 / 订阅已删除 / 已移除「名称」 / 已导入源「名称」（演示模式，未解析执行） / 读取文件失败 |
| 本地扫描 | 已登记 N 个本地文件 / 已为 N 首本地曲目匹配同名 .lrc 歌词 / 已从本地库移除「名称」 |
| 设置与其它 | 运行日志已清空 / 仅 Wi-Fi 下载：已开启 / 仅 Wi-Fi 下载：已关闭 / 已切换到「设备名」 / 已打开「已下载」：N 张专辑 / 还没有已下载的专辑 / 先挑一首歌 / 先挑一首歌再展开播放页 |

### 8.2 空状态（标题 / 说明 / 图标 / 动作按钮）
- 还没有最近播放 / 点开任意一首歌，它会自动出现在这里。 / clock / 去找首歌、去首页看看
- 暂时没有推荐 / 推荐来自已启用的音乐源，全部停用时这里为空。 / globe / 管理音乐源
- 还没有自建歌单 / 把喜欢的歌收进一个歌单，方便下次直接播。 / queue / 新建歌单
- 所有音乐源都已停用 / 聚合搜索只查已启用的源。去「音乐源」重新打开一个，或通过订阅添加新源。 / globe / 管理音乐源
- 没有找到「关键词」 / 换个关键词试试，或检查拼写。 / search / 清除关键词
- 这个来源没有「关键词」的结果 / 切回「全部来源」看看其它源，或换个关键词。 / search / 无
- 还没有已下载的歌曲 / 在专辑页或歌曲菜单里点下载，完成的曲目会列在这里。 / download / 无
- 「来源」下还没有歌单 / 这个来源暂时没有歌单；也可以去「音乐源」启用别的源。 / queue / 管理音乐源
- 还没有喜欢的歌曲 / 在任何歌曲上点一下爱心，就会出现在这里。你可以在首页或搜索里找歌。 / heart / 去首页看看
- 还没有本地音乐 / 选择一个文件夹，回响会扫描其中的音频文件，按文件夹分组。 / folder / 选择文件夹
- 这个歌单还没有歌曲 / 点「添加歌曲」，从音乐库里挑几首放进来。 / queue / 添加歌曲
- 这个歌单暂时没有曲目 / 稍后再来看看。 / queue / 无
- 播放队列是空的 / 播放任意歌曲后，队列会显示在这里。 / queue / 无
- 还没有下载任务 / 在专辑或单曲的下载入口开始下载，任务会显示在这里。 / download / 无
- 还没有音乐源 / 可通过订阅或导入插件文件添加。 / globe / 添加订阅、导入插件文件
- 还没有订阅 / 订阅一个远程地址，会展开成 1~N 个音乐源；也可以直接导入插件文件。 / globe / 添加订阅、导入插件文件
- 还没有运行日志 / 搜索、播放等操作会记录各源执行情况。 / note / 无
- 还没有歌单 / 点右上角新建一个歌单。 / note / 无
- 页面走丢了 / 链接可能已失效，回到首页继续浏览。 / info / 回到首页
- 详情页缺失：这张专辑不在库里 / 这个歌单不存在或已被删除 / 没有找到这位艺人 / 这个文件夹不在本地库里 —— 同样副文案 + 回到首页
- trackList 无数据时默认：这里还没有歌曲
- 歌词空态：这首歌的来源没有提供歌词 + 两条分支说明（见 3.8）

### 8.3 aria-label 原文（逐字）
静态（index.html）：
- 跳到主内容（skip-link）、主导航（sidebar）、主要（nav）、返回（#brand-back / #topbar-back / #float-back）
- 搜索（#topbar-search）、切换深浅色主题（#theme-toggle）、播放器（playerbar region）、底部导航（tabbar）
- 展开播放页（#pb-open、#pb-expand）、喜欢（#pb-like / #pb-like-c / #np-like）、播放或暂停（#pb-play / #np-play 随状态切换）
- 随机播放（#pb-shuffle / #np-shuffle）、上一首（#pb-prev / #np-prev）、下一首（#pb-next / #np-next）、循环模式：关闭（#pb-repeat / #np-repeat）
- 播放进度（#pb-track / #np-track，role=slider，带 aria-valuemin/max/now）、音量（#pb-volume / #np-volume）、静音（#pb-mute / #np-mute）
- 下载任务（#pb-downloads）、播放队列（#pb-queue / #np-queue）、正在播放（#nowplaying dialog）、收起播放页（#np-close）、更多操作（#np-more）
- 歌词或收起歌词（#np-lyrics）、睡眠定时器（#np-sleep）、播放设备（#np-device）、歌词文本（#np-lyrics-scroll region）、关闭（#sheet-close）、告诉屏幕阅读器的 sheet 标题关联（aria-labelledby=sheet-title）
动态（app.js）：
- 播放专辑：标题 / 播放歌单：名称 / 播放艺人：名称 / 播放：曲目名 / 更多操作：曲目名
- 喜欢 / 取消喜欢（行内与播放器爱心随状态切换）
- 从队列移除：曲目名；停用 X / 启用 X；源详情：X；订阅详情：X；下载进度：标题
- 搜索歌曲（input）、清空搜索（按钮）、深色主题（switch）、仅 Wi-Fi 下载（switch）、更多歌单操作（歌单页更多按钮）、排序方式（filter-rail role=group）

### 8.4 其它固定文案
- 应用名：回响 / RESONANCE（brand__sub）；页面标题后缀 ' · 回响 Resonance'；页面描述 '回响 Resonance —— 同一套界面覆盖手机与大屏的音乐播放器原型，含在线流媒体与本地音乐库。'
- 侧边栏：导航 '首页 / 搜索 / 音乐库 / 我喜欢的音乐 / 本地音乐 / 我的'；分组标题 '你的歌单'；底部 '切换到浅色' / '切换到深色'
- 底部 tabbar：首页 / 搜索 / 音乐库 / 我的
- 播放条默认：'未在播放' / '选择一首歌曲开始'；播放页默认：'未在播放' / '从首页或音乐库挑一首'；上下文行 '正在播放' + '—'；准备中 '准备播放中…' / '准备播放中'
- 我的页：头像 '响'、'听歌的人'、'免费账户 · 在线与本地同步'
- 关于：'回响 Resonance' + '版本 1.0 · 响应式原型'
- 歌词注释：'示例歌词 · 非原曲文本' / '来自同名 .lrc 文件'

---

## 9. 移植到 Flutter 时需注意的行为细节
1. 播放存在 520ms 的「取播放地址」等待态（pending）：列表行封面蒙层显示 spin、播放条与沉浸页播放键 data-loading、播放条标题显示 '准备播放中…'、沉浸页上下文行前缀 '准备播放中'；用户此时按播放键立即开始。
2. 顺序播放（repeat='off'）播到最后一首不循环：停止并把进度停在末尾；列表循环/单曲循环两端回绕。
3. 随机与循环互斥：开启随机不改变 repeat 值但循环按钮置灰（aria-pressed=false、is-inactive），关闭随机强制回到 'all'；随机的「上一首」走历史栈（≤200），不按列表顺序。
4. prev()：播放超过 4 秒先回到该曲开头，否则上一首。
5. 队列不持久化；喜欢/最近/搜索/自建歌单/主题/音量/歌词开关/歌词/设备/Wi-Fi/扫描登记/源/订阅/日志会持久化；下载任务与睡眠定时器不持久化。
6. 播放现场（queue/index/playing/shuffle/repeat）不持久化，但首次启动用内置数据兜底：Dark Side of the Moon 全专、index=3、暂停、context='专辑'。
7. 同名 .lrc 必须与音频在同一次文件夹选择中一起选中（浏览器安全限制）；本地扫描登记只保存文件名与时长。
8. 多源聚合搜索不做跨源去重：同一首歌在不同源会各自出现一行，来源由行尾标签与来源筛选条表达。
9. 音乐库分栏内容是「歌单」而不是歌曲列表；「已下载」栏是专辑网格 + 曲目列表。
10. 状态表达：正在播放 = 封面蒙层 eq 三柱 / 无封面时行首序号换成 eq；准备中 = spin；已下载 = 行内 '已下载' 徽标；当前行整行高亮（.track.is-current 背景 --accent-soft）。
