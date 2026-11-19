# 架构总览（现行）

> 单一架构真相源（**以代码为准，2026-11-13 校准**）。从 packages/* 代码与各文档提炼；实现细节见对应专题文档。

## 1. 一句话定位
resonance / 回响：纯客户端、无后端的全源音乐聚合播放器。本地扫描 / 本地自建 / 收藏三类本地源 + JSON 规则源（内置 6U / 歌曲宝 / GD音乐台 + demo_catalog）+ 插件源（MusicFree / 落雪），统一 MusicSource 契约，跨源聚合搜索、播放与歌单管理。

## 2. 包结构与依赖
~~~text
resonance_app（壳工程：只组装，无业务逻辑）
├── uiv2   现役 UI（Flutter，go_router）
└── ui     v1 UI（Flutter，已废弃，保留）
uiv2 / ui ──> core + player + crawler + db
crawler   ──> core + expr   （crawler 为 Flutter 包，含 JS 运行时）
player    ──> core
db        ──> core（SQLite 实现，Flutter 包）
~~~

| 包 | 类型 | 职责 |
|---|---|---|
| core | 纯 Dart（零运行时依赖） | 数据模型；MusicSource/Player/DAO 接口；SourceManager；RecentPlaysService；DownloadManager/AudioCache 抽象；BackupCodec/BackupService；LrcParser；PlaylistCodec；SourceLogBus；PlayProgress |
| expr | 纯 Dart | 表达式解析/执行（CSS/JSONPath/XPath/Regex）+ 组合语法（&& / || / ## / #）；依赖 html / xml / json_path |
| crawler | Flutter | 规则引擎（RuleConfig/Loader/Executor/ResponseHandler）、HTTP、RuleBasedMusicSource、插件适配（MusicFree/落雪，JS 运行时 flutter_inappwebview） |
| player | Flutter | just_audio 实现 Player（队列/四种播放模式/随机历史栈/状态流）+ audio_service 后台播放侧车 |
| db | Flutter | SQLite 持久化（sqflite / sqflite_common_ffi，schema **v4**）、**六类 DAO**、DownloadManager / AudioCache 实现 |
| ui | Flutter | v1 UI（Material3 + riverpod_generator，已废弃，壳工程不再依赖） |
| uiv2 | Flutter | 现役 UI（go_router StatefulShellRoute + 设计令牌 + SVG 图标） |

## 3. 关键运行流
- **搜索**：SourceManager.searchAll（并行等齐）与 searchStream（逐源先到先上屏）；单源失败不影响整体，结果按源分组合并展示。
- **播放**：播放地址解析（本地 localPath → 缓存命中 file:// → SourceManager.getPlayable）→ Player 播放 → 状态流同步 → 记录最近播放 + 播放进度（play_progress）。
- **歌词**：在 currentSongStream 漏斗处 ensureLyrics 写入 songs.lyric，按 key 去重并发。
- **持久化**：UI → Service/DAO → DatabaseProvider（SQLite），见 [01-data-schema](01-data-schema.md)。
- **离线缓存**：播放成功后后台另存完整文件（.part 临时名，完整才命中），见 [offline-cache](features/offline-cache.md)。
- **后台播放**：壳层 audio_service 侧车；**Android 已接线且配置齐全**；**iOS 已补 `UIBackgroundModes: audio`（2026-11-19），待 macOS/Xcode 验证**。

## 4. 音乐源清单
| 源 | sourceId | 类型 | 说明 |
|---|---|---|---|
| LocalScanSource | local_scan | local | 扫描设备目录（7 种音频格式） |
| LocalCustomSource | local_custom | local | 用户自建单曲（复用 songs 表 + sourceId 区分） |
| FavoriteSource | favorite | local | 跨源收藏；存 song_key + 标题/歌手/封面快照，优先快照渲染 |
| RuleBasedMusicSource | 规则定义 | rule | 一份 JSON 规则 = 一个源 |
| 6U（6uq） | 见规则文件 | rule | 内置规则源（assets/rules/6uq.json） |
| 歌曲宝（gequbao） | 见规则文件 | rule | 内置规则源（含人机验证流程） |
| gdstudio_netease | gdstudio_netease | rule | GD 音乐台映射源，见 [source-gdstudio](specs/source-gdstudio.md) |
| demo_catalog | demo_catalog | rule | 演示曲库（demo_source 独立 HTTP 服务，仅 Debug） |
| MusicFree / 落雪 | 插件 | plugin | 插件适配（.json / .js） |

## 5. 现状与历史
- 现役 UI 为 **uiv2**（go_router）；v1「packages/ui」已废弃（壳工程不再依赖）。
- 演进脉络见 [03-migration-history](03-migration-history.md)；数据库见 [01-data-schema](01-data-schema.md)；术语见 [02-glossary](02-glossary.md)。
