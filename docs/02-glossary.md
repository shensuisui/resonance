# 术语 / 属性表

> 汇总项目中反复出现的领域术语与配置键，供阅读文档与代码时对照。状态：现行 ｜ 更新：2026-11-13

## 1. 领域模型
| 术语 | 含义 |
|---|---|
| Song | 歌曲；全局唯一键 (id, sourceId) |
| song_key / globalKey | 跨源唯一引用，格式「sourceId:id」 |
| Playlist | 歌单；songKeys 有序列表，区分本地 UUID 歌单与导入源歌单 |
| SearchResult | 搜索结果，支持 page / offset / cursor 三种分页 |
| SourceType | 源类型：local / rule / plugin |
| SourceInfo | 源元信息（id / name / icon / enabled 等） |

## 2. 源与接口
| 术语 | 含义 |
|---|---|
| MusicSource | 所有音乐源的统一抽象接口（search/getSongDetail/getSongUrl/getLyrics 等） |
| SourceManager | 源注册 / 启停 / 并行聚合搜索 / 按源路由 |
| LocalScanSource / LocalCustomSource / FavoriteSource | 三类本地源（扫描 / 自建 / 收藏） |
| RuleBasedMusicSource | 用一份 JSON 规则包装成的源 |
| RuleConfig / RuleLoader / RuleExecutor / ResponseHandler | 规则数据、加载、执行、响应处理 |
| listRule / itemRules / PaginationRule | 规则内列表定位、字段提取、分页（page/offset/cursor） |

## 3. 表达式（expr）
| 术语 | 含义 |
|---|---|
| ParserType | parser 类型：CSS / JSONPath / XPath / Regex |
| CompoundType | 复合：chain（&&）、fallback（「||」）、净化（##）、分割（#） |
| @Json: / @XPath: | 显式指定解析器的前缀 |
| @JS: | JavaScript 表达式（预研 / 暂不支持，遇之报错） |
| 占位符 | HTTP / 规则中的 {baseUrl}、{keyword}、{page}、{id} 等替换 |

## 4. 播放与状态
| 术语 | 含义 |
|---|---|
| PlayMode | sequential / listLoop / singleLoop / shuffle |
| PlayerState | 播放器状态（当前曲、进度、时长、模式等） |
| 随机历史栈 | shuffle 模式下「上一首」回退用的历史栈 |
| 侧车（sidecar） | 不改 PlayerImpl，在壳层挂 audio_service 的后台播放方案 |

## 5. 持久化与服务
| 术语 | 含义 |
|---|---|
| DAO / DatabaseProvider | 数据访问接口 / SQLite 实现注入点 |
| RecentPlaysService | 最近播放业务（去重 / 移顶 / 500 上限） |
| SettingsDao / SettingsService | 设置键值对持久化 |
| DownloadManager | 下载任务管理（含缓存） |

## 6. 环境与开关
| 术语 | 含义 |
|---|---|
| RESONANCE_DRIVER | 是否启用 Flan 调试/驱动扩展（--dart-define） |
| RESONANCE_DEMO_BASE_URL | Debug 下演示曲库服务地址 |
| demo_source | 独立 Dart HTTP 演示曲库服务（仅开发） |
