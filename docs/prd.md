# 全源音乐聚合播放器 PRD

| 文档版本 | 1.0 |
| :--- | :--- |
| 更新日期 | 2026-08-24 |
| 状态 | 设计完成，待开发 |
| 技术栈 | Flutter（纯客户端，无后端） |

---

## 1. 产品概述

### 1.1 产品背景
用户希望在单一 APP 中搜索和播放来自不同音乐平台、本地存储甚至自建歌单的歌曲，无需在多个应用间切换。现有解决方案受限于平台或规则固化，难以动态扩展。

### 1.2 产品目标
构建一个**无后端、纯客户端**的聚合音乐播放器，通过**可动态配置的规则引擎**和**插件适配机制**，实现"听取所有来源的音乐"。用户可自由添加、启用或禁用音乐源，支持在线流媒体播放、离线下载缓存、歌单管理、跨源聚合搜索及最近播放。

### 1.3 核心价值
- **全源聚合**：本地音乐 + 在线平台 + 自建曲库 + 第三方插件生态，一个 APP 内搜索和播放。
- **极致扩展**：无需代码，通过 JSON 规则文件或导入外部插件即可支持新平台。
- **数据自主**：所有数据存储在本地，无需后端，保护隐私，离线可用。

---

## 2. 用户角色与场景

| 角色 | 典型场景 |
| :--- | :--- |
| **普通听众** | 跨平台搜索某首歌曲，收藏到统一歌单；下载到本地离线收听。 |
| **音乐爱好者** | 手动整理本地无损音乐库，与在线资源混合播放；使用"我喜欢"功能收藏各类来源歌曲。 |
| **高级用户/规则贡献者** | 编写或导入 JSON 规则文件，自行适配小众音乐网站；导入落雪、MusicFree 等社区插件。 |

---

## 3. 功能需求

### 3.1 音乐来源管理（核心）

#### 3.1.1 音乐源抽象层
所有音乐来源必须实现统一的 `MusicSource` 接口，向上层提供搜索、获取详情、获取歌单等能力。源可被动态注册、启用/禁用。

#### 3.1.2 本地音乐源（三合一）

- **本地扫描源**
  自动扫描设备指定目录（可配置）下的音频文件，提取元数据（标题、艺术家、专辑、时长等），构建本地曲库。支持按文件名/标签搜索，按文件夹自动生成歌单。

- **本地自建源**
  用户手动添加单首歌曲（本地文件路径或网络 URL），自定义标题、艺术家等信息，数据持久化在本地。支持搜索和归入歌单。

- **最喜欢源**
  跨源收藏系统。用户在任何源中标记"喜欢"的歌曲，自动汇集到该源。歌曲仅记录唯一标识，不复制文件。支持在"最喜欢"源内搜索和播放。

#### 3.1.3 插件兼容适配器

- **落雪音乐适配器**：解析 `.lx` 插件文件，转换为内部搜索/播放调用。
- **MusicFree 适配器**：解析 `.mf` 插件文件，遵循其规范实现源行为。
- **未来扩展**：支持更多第三方插件格式（如 Listen1 等），每种格式一个适配器实现。

**默认插件源地址：**

| 适配器 | 源类型 | 加载地址（默认） |
|--------|--------|------------------|
| 落雪音乐适配器 | `.lx` 插件 | `https://fastly.jsdelivr.net/gh/Huibq/keep-alive/render_api.js` |
| MusicFree 适配器 | `.mf` 插件列表 | `https://fastly.jsdelivr.net/gh/Huibq/keep-alive/Music_Free/myPlugins.json` |

> 落雪适配器：该地址返回落雪音乐插件脚本，APP 启动时可下载并解析为内置源。
> MusicFree 适配器：该地址返回插件集合的 JSON 索引，APP 可解析其中的多个插件地址，动态加载 MusicFree 插件。

以上地址作为适配器的**默认远程资源**，用户也可在设置中手动导入本地或自定义地址的插件文件。

#### 3.1.4 自有规则引擎源
通过 JSON 规则文件描述任意在线音乐平台的数据提取逻辑。支持多种解析器与高级特性，规则文件存放于 `fm_app/assets/rules/` 或用户导入目录，APP 启动时自动加载为音乐源。

#### 3.1.5 源管理界面（待定 UI）
- 源列表展示，显示名称、图标、类型（本地/插件/规则），启用/禁用开关。
- 支持从本地文件导入新规则或插件。
- 支持从 URL 下载更新规则（远期可选）。
- 内置预置源推荐（如主流平台规则示例）。

---

### 3.2 搜索与聚合
- **跨源聚合搜索**：用户输入关键词后，并行请求所有已启用的源，将结果合并展示。
- 搜索结果去重策略：暂不对跨源歌曲去重（不同源可能有不同音质/格式），由用户选择播放哪个源的版本。
- 支持分页加载（若源支持）。本地源全量搜索不分页。
- 搜索历史与热门推荐（后期功能，本期可选）。

---

### 3.3 播放控制

#### 3.3.1 基础播放
- 在线流媒体播放，支持常见音频格式（MP3/AAC/FLAC 等）。
- 下载缓存：将歌曲下载到本地存储，后续播放直接使用本地文件。支持下载队列管理（暂停/取消/删除缓存）。
- 播放器基本功能：播放/暂停、上下曲、进度条拖动、音量控制。
- **（待定）后台播放、锁屏控制、通知栏控制**。

#### 3.3.2 最近播放列表
系统自动维护一个"最近播放"列表，记录用户点击播放过的歌曲（跨所有源），按播放时间倒序排列。

- **触发条件**：用户在任何界面（搜索、歌单、本地、喜欢等）点击播放歌曲时，自动将歌曲加入最近播放列表。
- **唯一性**：同一首歌重复播放时，不会重复添加，而是将其移动到列表顶部（更新播放时间）。
- **存储**：在 SQLite 中新增 `recent_plays` 表，记录歌曲全局唯一键和播放时间戳。
- **上限**：列表最多保留最近播放的 **500** 首歌曲，超出时自动移除最旧的记录（上限可配置）。
- **展示**：作为一个独立入口（如侧边栏或首页快捷入口），展示为歌曲列表，支持点击播放、添加到歌单、喜欢等操作。
- **与"最喜欢"的关系**：相互独立。最近播放是行为记录，喜欢是用户主动标记。

#### 3.3.3 播放模式
播放器支持四种播放模式，用户可在播放界面或迷你播放器上切换，控制播放队列的循环和随机行为。

| 模式 | 行为描述 |
| :--- | :--- |
| **列表循环** (List Loop) | 播放完当前列表最后一首后，自动跳转到第一首继续播放，循环整个列表。 |
| **单曲循环** (Single Loop) | 当前歌曲播放结束后自动重放，不跳转下一首。 |
| **随机播放** (Shuffle) | 在播放队列中随机选择下一首；手动点击上一首遵循随机历史栈。 |
| **顺序播放** (Sequential) | 播放完列表最后一首后停止，不自动循环。 |

- 播放模式状态全局生效，切换列表时保留当前模式。
- 随机播放模式下，"上一首"行为应返回随机历史中的上一首（维护播放历史栈），而非列表中的前一个索引。
- 播放模式保存在本地键值存储，应用重启后恢复为上次设置的模式（默认列表循环）。

---

### 3.4 歌单管理
- **创建/编辑/删除歌单**：歌单包含歌曲列表（引用唯一标识，不复制歌曲文件）。
- **添加歌曲到歌单**：从搜索结果、正在播放、本地文件等处添加。
- **导入/导出**：
  - 支持导入外部歌单格式（M3U/PLS/JSON）转换为内部歌曲引用。
  - 支持导出内部歌单为通用格式。
- **源歌单导入**：若规则源支持歌单接口，可输入源歌单 ID 直接导入。
- 歌单内支持排序、批量操作。

### 3.5 收藏与"最喜欢"
- 用户在任何歌曲上点击"喜欢"，歌曲加入最喜欢源。
- 最喜欢歌曲列表可在专门的"最喜欢"源中查看和播放。
- 取消喜欢时从该源移除。
- 最喜欢数据持久化，与歌单独立。

### 3.6 本地音乐管理
- 扫描进度提示，增量更新策略。
- 本地歌曲可编辑元信息（仅限自建歌曲，扫描文件只读）。
- 本地歌曲支持从设备删除文件（需确认）。

---

## 4. 包架构

采用多包划分，上层业务仅依赖抽象接口。

```
┌─────────────────────────────────────────────────────┐
│                   fm_app (壳工程)                     │
│              assets/rules/  assets/plugins/          │
└──────────────┬──────────────────────────┬───────────┘
               │                          │
               ▼                          ▼
┌──────────────────────────┐  ┌────────────────────────┐
│  ui (Flutter package)    │  │  player (Flutter)      │
│  Riverpod, 页面, Widget  │  │  just_audio 实现       │
│  主题, 路由              │  │  Player 接口           │
└──────┬───────────────────┘  └────────┬───────────────┘
       │                              │
       │  ┌───────────────────────────┘
       │  │
       ▼  ▼
┌──────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
│  core (纯 Dart)   │  │  crawler (纯 Dart)    │  │  expr (纯 Dart)      │
│  数据模型          │  │  规则执行引擎         │  │  表达式解析抽象层     │
│  MusicSource 接口  │  │  插件适配器           │  │  CSS/JSONPath/       │
│  本地源（扫描/自建/   │  │  (落雪/MusicFree)    │  │  XPath/Regex 解析器  │
│  最喜欢）           │  │  HTTP 请求封装       │  │                     │
│  SourceManager     │  │  RuleBasedSource    │  │                     │
│  Player 接口       │  │                     │  │                     │
│  持久化层 (SQLite)  │  │                     │  │                     │
└──────────────────┘  └──────────────────────┘  └──────────────────────┘
```

### 4.1 包依赖关系

```
fm_app → ui
ui → core + player + crawler
crawler → core + expr
player → core
```

### 4.2 各包职责

#### `core`（纯 Dart）
- **数据模型**：`Song`, `Album`, `Artist`, `Playlist`, `Lyrics`, `SourceRule` — 纯数据类，`sourceId` 字段标记来源
- **MusicSource 抽象接口**：`search()`, `getSongDetail()`, `getSongUrl()`, `getLyrics()` 等
- **本地源实现**：`LocalScanSource`, `LocalCustomSource`, `FavoriteSource`
- **SourceManager**：源的注册/启用/禁用/聚合搜索调度
- **Player 抽象接口**：`play()`, `pause()`, `seek()`, `state` 等，纯 Dart 定义
- **持久化层**：SQLite 数据库、DAO（Song, Playlist, RecentPlays, Favorites）

#### `crawler`（纯 Dart，依赖 `core` + `expr`）
- **规则执行引擎**：`RuleExecutor` — 加载规则配置，执行搜索/详情/歌词/歌单的全流程
- **响应处理器**：`ResponseHandler` — 根据 responseType 处理 HTML/JSON/Text 响应
- **规则链与特性**：`&&` 链式调用、`||` 备用规则、`##` 净化、`#` 分割、模板拼接
- **HTTP 请求封装**：dio 封装，支持 GET/POST/headers/占位符替换
- **插件适配器**：`LxMusicAdapter`, `MusicFreeAdapter` — 解析第三方插件格式
- **RuleBasedMusicSource**：实现 `MusicSource` 接口，聚合多个 JSON 规则实例

#### `expr`（纯 Dart，无外部依赖）
- **表达式解析器 AST**：CSS 选择器、JSONPath、XPath、Regex 各自的解析结果类型
- **解析器实现**：`CSSParser`, `JSONPathParser`, `XPathParser`, `RegexParser`
- **抽象层**：统一的 `ExpressionParser` 接口，`ParseResult` 结果类型
- **不包含**：HTTP 请求、规则执行逻辑、链式调用

#### `player`（Flutter，依赖 `core`）
- `PlayerImpl` — 实现 `core` 的 `Player` 接口，底层用 `just_audio`
- 音频焦点、音效、均衡器等平台相关处理

#### `ui`（Flutter，依赖 `core` + `player` + `crawler`）
- **状态管理**：Riverpod Provider / Notifier
- **页面**：发现页、搜索页、歌单页、播放页、源管理页、设置页
- **公共组件**：通用 Widget、主题、导航、路由

---

## 5. 表达式引擎（`expr` 包）

### 5.1 表达式类型

| 前缀/标识 | 类型 | 适用内容 | 示例 |
| :--- | :--- | :--- | :--- |
| `@XPath:` 或 `//` | XPath 表达式 | HTML / XML | `@XPath://div[@class='title']/text()` |
| `@Json:` 或 `$.` | JSONPath 表达式 | JSON 数据 | `@Json:$.data.books[0].title` |
| `@CSS:` 或 **无前缀** | CSS 选择器 | HTML | `div.title@text` |
| `@Regex:` 或 `:` | 正则表达式 | 纯文本 | `:title\s*:\s*(.*?)\s*\n` |
| `@JS:` | JavaScript 表达式（预研） | 任意 | `@JS:md5(keyword + 'salt')` |

- **CSS 提取后缀**：`@text`（文本）、`@html`（HTML 内容）、`@attr`（属性值，如 `img@src`）

### 5.2 高级特性（由 `crawler` 的 `RuleExecutor` 实现）

- **规则链（`&&`）**：多条规则串联，前一条输出作为后一条输入。
  例：`div.book-info && h1.title && @text`
- **备用规则（`||`）**：当前规则未匹配到时使用备用规则。
  例：`@CSS:.cover@src || @CSS:.thumb@src`
- **净化修饰符（`##`）**：移除/替换匹配内容。
  例：`div.content##<.*?>||`（移除所有 HTML 标签）
- **分割修饰符（`#`）**：按指定字符分割成列表。
  例：`div.tags#,`
- **模板拼接**：`{{result}}` 代表前一步提取值。
  例：`@Json:$.id@/novel/{{result}}`

> `expr` 包负责表达式解析（String → AST），`crawler` 包负责执行链、备用、净化、分割等组合逻辑。

### 5.3 JavaScript 表达式
预留 `@JS:` 前缀标识，评估 `flutter_js` 等运行时集成。当前版本遇到 `@JS:` 抛出明确错误提示"JS 表达式即将支持"。预研任务包括：沙箱执行环境、输入输出规范、执行时间限制与安全防护。

---

## 6. 规则文件结构

规则文件为 JSON 格式，存放于 `fm_app/assets/rules/`。包含以下节点（均可选，`source` 必填）：

```json
{
  "source": { "id": "...", "name": "...", "baseUrl": "...", "icon": "..." },
  "search": { ... },
  "songDetail": { ... },
  "playlist": { ... },
  "lyric": { ... }
}
```

### 6.1 `search` 节点字段

| 字段 | 类型 | 说明 |
| :--- | :--- | :--- |
| `url` | string | 请求路径，支持 `{keyword}`, `{page}` 占位符 |
| `method` | string | GET / POST |
| `headers` | object | 自定义请求头，支持 `{baseUrl}` 占位 |
| `responseType` | string | `json` / `html` / `text` |
| `listRule` | string | 定位歌曲列表容器的规则表达式 |
| `itemRules` | object | 从每个列表项提取字段的规则映射 |
| `pagination` | object | 分页配置 |

**`itemRules` 支持的字段：**
`id`, `title`, `artist`, `album`, `cover`, `duration`, `playUrl`, `lyricUrl`, `quality`, 以及自定义字段（存入 `Song.extra`）。

**`pagination` 字段：**
- `type`：`page` / `offset` / `cursor`
- `pageParam`（page 类型）、`offsetParam`+`limitParam`+`limitValue`（offset 类型）、`cursorParam`+`cursorRule`（cursor 类型）
- `totalRule`（可选）：总数提取规则
- `totalRegex`（可选）：净化总数的正则

### 6.2 `songDetail` 节点字段
同 `search`，但通常 `listRule` 指向单个对象，`itemRules` 提取 `playUrl`、`lyricUrl`、`cover` 等。`url` 支持 `{id}` 占位符。

### 6.3 `lyric` 节点字段

用于独立获取歌词内容，支持三种场景：

| 场景 | 行为 |
| :--- | :--- |
| `songDetail` 返回 `lyric` 文本 | 直接使用，不再请求 |
| `songDetail` 返回 `lyricUrl` | 用 `{lyricUrl}` 占位符请求 `lyric` 节点 |
| 无歌词信息 | 用 `{id}` 占位符请求 `lyric` 节点 |

```json
"lyric": {
  "url": "{lyricUrl}",
  "method": "GET",
  "headers": {},
  "responseType": "text",
  "listRule": "$.data",
  "contentRule": "$.lyric"
}
```

- `responseType` 为 `text` 时，响应体直接作为歌词文本，`contentRule` 可省略。
- `listRule` 未指定时，`contentRule` 直接作用于整个响应根。

### 6.4 `playlist` 节点字段
同 `search`，用于导入源歌单。`url` 支持 `{id}`（源歌单 ID）。

### 6.5 完整规则文件示例

```json
{
  "source": {
    "id": "example_music",
    "name": "示例音乐源",
    "baseUrl": "https://api.example.com",
    "icon": "https://example.com/icon.png"
  },
  "search": {
    "url": "/search?keyword={keyword}&page={page}",
    "method": "GET",
    "responseType": "json",
    "listRule": "$.data.songs",
    "itemRules": {
      "id": "id",
      "title": "name",
      "artist": "artist.name",
      "cover": "cover_url",
      "duration": "duration_seconds",
      "playUrl": "url",
      "lyricUrl": "lyric_url"
    },
    "pagination": {
      "type": "cursor",
      "cursorParam": "cursor",
      "cursorRule": "$.data.nextCursor"
    }
  },
  "songDetail": {
    "url": "/song?id={id}",
    "method": "GET",
    "responseType": "json",
    "listRule": "$.data",
    "itemRules": {
      "playUrl": "play_url",
      "cover": "cover_large",
      "lyricUrl": "lyric_url"
    }
  },
  "lyric": {
    "url": "{lyricUrl}",
    "method": "GET",
    "responseType": "text"
  },
  "playlist": {
    "url": "/playlist?id={id}",
    "method": "GET",
    "responseType": "json",
    "listRule": "$.data.songs",
    "itemRules": {
      "id": "id",
      "title": "name",
      "artist": "artist",
      "cover": "cover_url",
      "duration": "duration",
      "playUrl": "url"
    }
  }
}
```

---

## 7. 数据模型

### 7.1 Song（歌曲）

| 字段 | 类型 | 说明 |
| :--- | :--- | :--- |
| id | String | 源内歌曲 ID |
| sourceId | String | 来源标识，组成全局唯一键 |
| title | String | 歌名 |
| artist | String | 艺术家 |
| album | String? | 专辑 |
| coverUrl | String? | 封面 URL |
| duration | int? | 时长（秒） |
| playUrl | String? | 播放地址（可能临时） |
| lyricUrl | String? | 歌词文件地址 |
| lyric | String? | 歌词文本（若已获取） |
| localPath | String? | 本地缓存路径 |
| extra | Map | 源自定义扩展字段 |

**唯一约束**：`(id, sourceId)` 联合主键。

### 7.2 Playlist（歌单）

| 字段 | 类型 | 说明 |
| :--- | :--- | :--- |
| id | String (UUID) | 主键 |
| name | String | 歌单名称 |
| songKeys | List\<String\> | 包含的歌曲全局键列表 |
| sourceId | String? | 若为导入源歌单，记录来源 ID |
| sourcePlaylistId | String? | 源歌单原始 ID |
| createdTime | DateTime | |
| modifiedTime | DateTime | |

### 7.3 其他表

**recent_plays（最近播放）**

| 字段 | 类型 | 说明 |
| :--- | :--- | :--- |
| song_key | TEXT PK | 歌曲全局唯一键 (sourceId:id) |
| played_at | INTEGER | 播放时间戳（Unix 毫秒） |

**favorites（最喜欢）**

| 字段 | 类型 | 说明 |
| :--- | :--- | :--- |
| song_key | TEXT PK | 歌曲全局唯一键 |
| favorite_time | INTEGER | 收藏时间戳 |

**local_custom_songs（自建歌曲）**：同 songs 表结构，通过 `sourceId='local_custom'` 区分，或独立表。

---

## 8. 关键流程

### 8.1 跨源搜索流程
1. 用户在搜索框输入关键词。
2. `SourceManager` 获取所有已启用源。
3. 并行调用 `source.search(keyword, page:1)`。
4. 各源返回 `SearchResult`（包含歌曲列表和分页信息）。
5. 管理器汇总所有歌曲列表，合并后展示（标注来源）。
6. 用户滑动到底部时，管理器对支持分页的源继续加载下一页，追加到结果中。

### 8.2 点击播放流程

**播放队列规则：**

| 场景 | 播放队列 |
|------|----------|
| 从搜索结果/本地/最喜欢/最近播放列表点击播放 | 最近播放列表 |
| 手动选择歌单并点击"播放全部" | 当前歌单 |

**执行步骤：**
1. 用户点击歌曲 → 获取播放地址（调用对应源的 `getSongDetail`）。
2. 歌曲加入最近播放列表（去重，移至顶部，更新播放时间）。
3. 判断用户是否在歌单"播放全部"操作中：
   - 是 → 队列 = 当前歌单列表。
   - 否 → 队列 = 最近播放列表。
4. 启动播放器，从点击歌曲位置开始播放。

**注意**：播放器始终维护一个当前队列，切换队列时重置播放模式和索引。

### 8.3 歌词获取流程
1. `songDetail` 返回 `lyric` 文本 → 直接使用。
2. 返回 `lyricUrl` → 调用 `lyric` 节点请求，URL 占位 `{lyricUrl}`。
3. 无歌词信息 → 调用 `lyric` 节点请求，URL 占位 `{id}`。
4. 解析并缓存歌词文本到 `Song.lyric`。

### 8.4 下载缓存流程
1. 用户点击下载按钮。
2. `DownloadManager` 检查歌曲是否已有本地缓存，若有则返回成功。
3. 若需要获取播放地址，调用对应源的 `getSongDetail` 取得最新 `playUrl`。
4. 使用 dio 下载文件到应用缓存目录，支持断点续传（可选）。
5. 下载完成后更新 `Song` 表的 `localPath`，通知 UI 更新状态。

---

## 9. 项目目录结构

```
fm/
├── .fvm/
│   └── fvm_config.json          # FVM 版本锁定 3.47.1
├── fm_app/                       # 壳工程
│   ├── assets/
│   │   ├── rules/                # 自有规则文件（.json）
│   │   │   ├── netease.json
│   │   │   ├── kugou.json
│   │   │   └── ...
│   │   └── plugins/              # 第三方插件文件
│   │       ├── lx/
│   │       └── mf/
│   ├── lib/
│   │   └── main.dart
│   └── pubspec.yaml
├── packages/
│   ├── core/                     # 核心模块（纯 Dart）
│   │   └── lib/
│   │       ├── core.dart
│   │       ├── src/
│   │       │   ├── models/
│   │       │   │   ├── song.dart
│   │       │   │   ├── playlist.dart
│   │       │   │   └── source_rule.dart
│   │       │   ├── sources/
│   │       │   │   ├── abstract_music_source.dart
│   │       │   │   ├── local_scan_source.dart
│   │       │   │   ├── local_custom_source.dart
│   │       │   │   └── favorite_source.dart
│   │       │   ├── services/
│   │       │   │   ├── source_manager.dart
│   │       │   │   └── download_manager.dart
│   │       │   ├── db/
│   │       │   │   ├── database.dart
│   │       │   │   ├── song_dao.dart
│   │       │   │   ├── playlist_dao.dart
│   │       │   │   └── recent_dao.dart
│   │       │   └── player/
│   │       │       └── player_interface.dart
│   │       └── src/core_base.dart
│   ├── expr/                     # 表达式解析抽象层（纯 Dart）
│   │   └── lib/
│   │       ├── expr.dart
│   │       └── src/
│   │           ├── parsers/
│   │           │   ├── css_parser.dart
│   │           │   ├── xpath_parser.dart
│   │           │   ├── jsonpath_parser.dart
│   │           │   └── regex_parser.dart
│   │           └── expression.dart
│   ├── crawler/                  # 远程源实现（纯 Dart）
│   │   └── lib/
│   │       ├── crawler.dart
│   │       └── src/
│   │           ├── engine/
│   │           │   ├── rule_loader.dart
│   │           │   ├── rule_executor.dart
│   │           │   └── response_handler.dart
│   │           ├── adapters/
│   │           │   ├── lxmusic_adapter.dart
│   │           │   └── musicfree_adapter.dart
│   │           ├── http/
│   │           │   └── http_client.dart
│   │           └── rule_based_source.dart
│   ├── player/                   # 播放器实现（Flutter）
│   │   └── lib/
│   │       ├── player.dart
│   │       └── src/
│   │           └── player_impl.dart
│   └── ui/                       # UI 模块（Flutter）
│       └── lib/
│           ├── ui.dart
│           └── src/
│               ├── providers/    # Riverpod
│               ├── pages/        # 各页面
│               ├── widgets/      # 通用组件
│               ├── theme/        # 主题
│               └── router/       # 路由
├── docs/
│   └── prd.md
├── AGENTS.md
└── .gitignore
```

---

## 10. 分期计划

### 第一期：基础设施
1. 数据模型定义（Song, Playlist, 等）— `core`
2. `MusicSource` 抽象接口 — `core`
3. 表达式解析器（CSS/JSONPath/XPath/Regex）— `expr`
4. 本地文件源（LocalScanSource）— `core`
5. 播放器抽象接口 + just_audio 实现 — `core` + `player`
6. 持久化层（SQLite schema + DAO）— `core`
7. `SourceManager` 基础框架 — `core`

### 第二期：在线源与规则引擎
1. 规则执行引擎（RuleExecutor, ResponseHandler）— `crawler`
2. HTTP 请求封装 — `crawler`
3. RuleBasedMusicSource — `crawler`
4. 至少一个在线规则源
5. 搜索流程打通

### 第三期：UI 与用户体验
1. Riverpod 状态管理 — `ui`
2. 基础页面框架（搜索、播放、歌单）
3. 插件适配器（落雪、MusicFree）— `crawler`
4. 下载缓存 — `core`
5. 最近播放、最喜欢