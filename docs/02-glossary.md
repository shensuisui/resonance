# 术语 / 属性表

> 汇总项目中反复出现的领域术语与配置键（以代码为准，2026-11-13 校准）。

## 1. 领域模型
| 术语 | 含义 |
|---|---|
| Song | 歌曲；全局唯一键 (id, sourceId) |
| song_key / globalKey | 跨源唯一引用，格式「sourceId:id」 |
| Playlist | 歌单；songKeys 有序，含 songSnapshots、coverUrl；id 由调用方提供（导入歌单 id=import_<hash>） |
| SearchResult | 搜索结果，支持 page / offset / cursor 三种分页 |
| SourceType | 源类型：local / rule / plugin |
| SourceInfo | 源元信息（id / name / icon / enabled 等） |
| PlayProgress | 播放进度（queue_kind / queue_id / song_key / position_ms / updated_at） |

## 2. 源与接口
| 术语 | 含义 |
|---|---|
| MusicSource | 统一接口：search / getSongDetail / getSongUrl / getPlayable / getLyrics / getAlbum / getArtist / getPlaylist / getPlaylistSongs / getPlaylistList / init / dispose |
| SourceManager | register / unregister / setSourceEnabled / searchAll / searchStream / getSongDetail / getPlayable / getLyrics / initAll |
| LocalScanSource / LocalCustomSource / FavoriteSource | 三类本地源（扫描 / 自建 / 收藏） |
| RuleBasedMusicSource | 用一份 JSON 规则包装成的源 |
| RuleConfig / RuleLoader / RuleExecutor / ResponseHandler | 规则数据 / 加载 / 执行 / 响应 |
| listRule / itemRules / PaginationRule | 列表定位 / 字段提取 / 分页（page / offset / cursor / size） |

## 3. 表达式（expr）
| 术语 | 含义 |
|---|---|
| ParserType | css / jsonPath / xPath / regex |
| CompoundType | none / chain（&&）/ fallback（||） |
| 后处理 | 净化（##pattern||replace）与分割（#分隔符）是 Expression 上的 sanitizePattern / splitChar，**不是** CompoundType 取值 |
| @Json: / @XPath: | 显式指定解析器的前缀 |
| @JS: | **未实现**；无解析分支，会退化为 CSS 选择器解析（无专属报错） |
| 占位符 / 模板 | {baseUrl}/{keyword}/{page}/{id} 等；模板拼接用 ${表达式} |

## 4. 播放与状态
| 术语 | 含义 |
|---|---|
| PlayMode | sequential / listLoop / singleLoop / shuffle |
| PlayerState | 枚举：idle / loading / playing / paused / stopped / error（进度/时长/模式在 Player 接口） |
| 随机历史栈 | shuffle 模式下「上一首」回退用的历史栈 |
| 侧车（sidecar） | 不改 PlayerImpl，在壳层挂 audio_service 的后台播放方案 |

## 5. 持久化与服务
| 术语 | 含义 |
|---|---|
| DAO / DatabaseProvider | 数据访问接口（6 类）/ SQLite 实现注入点 |
| RecentPlaysService | 最近播放业务（去重 / 移顶 / 500 上限） |
| SettingsDao | 设置键值对持久化（无 SettingsService） |
| DownloadManager / AudioCache | 下载任务 / 播放缓存（两者语义区分：AudioCache 不写 localPath） |
| BackupCodec / BackupService | 整包备份编解码 / 导入导出服务 |

## 6. UI 层（uiv2）
| 术语 | 含义 |
|---|---|
| go_router | 实际路由框架（StatefulShellRoute.indexedStack 保活一级页） |
| navProvider / NavNotifier | 业务侧路由门面（go / back / needsBack），底层调 go_router |
| Catalog 展示元数据 | Debug 时由壳工程注入 /catalog.json，Release 不打包 |
| SubscriptionHost / PluginHost | 订阅 / 插件宿主注入点 |

## 7. 环境与开关
| 术语 | 含义 |
|---|---|
| RESONANCE_DRIVER | 已无 App 侧实际使用（仅 v1 shimmer_box 遗留读取；启动脚本仍传，属遗留） |
| RESONANCE_DEMO_BASE_URL | Debug 下演示曲库服务地址 |
| demo_source | 独立 Dart HTTP 演示曲库服务（仅开发） |
