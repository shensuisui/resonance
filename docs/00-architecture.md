# 架构总览（现行）

> 单一架构真相源。从 [prd](product/prd.md)、[summary-s1-s3](summaries/summary-s1-s3.md) 及各包 README 提炼；实现细节见对应专题文档。
> 状态：现行 ｜ 更新：2026-11-13

## 1. 一句话定位
resonance / 回响是一个**纯客户端、无后端**的全源音乐聚合播放器：本地扫描 / 本地自建 / 收藏三类本地源 + JSON 规则源 + 插件源（MusicFree / 落雪），统一「MusicSource」契约，做跨源聚合搜索、播放与歌单管理。

## 2. 包结构与依赖
~~~text
resonance_app（壳工程：只组装，无业务逻辑）
├── uiv2   现役 UI（Flutter，OpenDesign 原型还原）
└── ui     v1 UI（Flutter，已废弃，保留）
uiv2 / ui ──> core + player + crawler (+ db)
crawler   ──> core + expr
player    ──> core
db        ──> core（SQLite 实现，Flutter 包）
~~~

| 包 | 类型 | 职责 |
|---|---|---|
| core | 纯 Dart | 数据模型、MusicSource/Player/DAO 接口、SourceManager、RecentPlaysService、DownloadManager 抽象 |
| expr | 纯 Dart | 表达式解析/执行（CSS / JSONPath / XPath / Regex）+ 复合表达式 |
| crawler | 纯 Dart | 规则引擎（RuleConfig/Loader/Executor/ResponseHandler）、HTTP、RuleBasedMusicSource、插件适配 |
| player | Flutter | just_audio 实现 Player（队列/四种播放模式/随机历史栈/状态流） |
| db | Flutter | SQLite 持久化（sqflite / sqflite_common_ffi）、五类 DAO、DownloadManager 实现 |
| ui | Flutter | v1 UI（Material3 + riverpod_generator），**已废弃** |
| uiv2 | Flutter | 现役 UI（自有路由 / 设计令牌 / SVG 图标，无需代码生成） |

## 3. 关键运行流
- **搜索**：SourceManager.searchAll 并行所有已启用源，单源失败不影响整体，结果按源分组合并展示。
- **播放**：播放地址解析三支（本地 localPath → 缓存命中 file:// → SourceManager.getPlayable）→ Player 播放 → 状态流同步 UI → 记录最近播放。
- **歌词**：在 currentSongStream 唯一漏斗处 ensureLyrics 写入 songs.lyric，按 key 去重并发。
- **持久化**：UI → Service/DAO → DatabaseProvider（SQLite），见 [01-data-schema](01-data-schema.md)。
- **离线缓存**：播放成功后后台另存完整文件（「.part」临时名，完整才算命中），设置页开关，见 [offline-cache](features/offline-cache.md)。
- **后台播放**：壳层 audio_service「侧车」（Android 一期），通知为渲染层，PlayMode 映射为 repeat/shuffle。

## 4. 音乐源清单
| 源 | sourceId | 类型 | 说明 |
|---|---|---|---|
| LocalScanSource | local_scan | local | 扫描设备目录（多种音频格式） |
| LocalCustomSource | local_custom | local | 用户自建单曲 |
| FavoriteSource | favorite | local | 跨源收藏（只存 song_key，回源取详情） |
| RuleBasedMusicSource | 规则定义 | rule | 一份 JSON 规则 = 一个源 |
| demo_catalog | demo_catalog | rule | 演示曲库（demo_source 独立 HTTP 服务，仅 Debug） |
| gdstudio_netease | gdstudio_netease | rule | GD 音乐台映射源，见 [source-gdstudio](specs/source-gdstudio.md) |
| MusicFree / 落雪 | 插件 | plugin | .mf（JSON 规则）/ .lx（JS 运行时）适配 |

## 5. 现状与历史
- 现役 UI 为 **uiv2**；v1「packages/ui」已废弃（入口已切 uiv2）。
- 演进脉络（更名、两套 UI、配表外移、SQLite 落地、后台播放、导入导出）见 [03-migration-history](03-migration-history.md)。
- 数据库结构见 [01-data-schema](01-data-schema.md)；术语见 [02-glossary](02-glossary.md)。
