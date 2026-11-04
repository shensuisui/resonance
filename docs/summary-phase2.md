# 第二期总结：在线源与规则引擎

| 完成日期 | 2026-08-24 |
| :--- | :--- |
| 范围 | Step 1–6 |
| 涉及包 | core, crawler |

---

## 完成步骤

| 步骤 | 文档 | 包 | 状态 |
| :--- | :--- | :--- | :--- |
| 1. LocalCustomSource + FavoriteSource | `docs/step2-1-local-sources.md` | core | ✅ |
| 2. 创建 crawler 包 + HTTP 封装 | `docs/step2-2-crawler-http.md` | crawler | ✅ |
| 3. 规则执行引擎 | `docs/step2-3-rule-executor.md` | crawler | ✅ |
| 4. RuleBasedMusicSource | `docs/step2-4-rule-based-source.md` | crawler | ✅ |
| 5. 插件下载 + 适配器 | `docs/step2-5-plugin-adapters.md` | crawler | ✅ |
| 6. 初始规则文件 + 搜索流程打通 | `docs/step2-6-search-flow.md` | resonance_app+crawler | ✅ |

## 新增包

### crawler（纯 Dart，依赖 core + expr + dio）

| 模块 | 文件 | 说明 |
| :--- | :--- | :--- |
| HTTP 封装 | `http/http_client.dart` | dio 封装，GET/POST/占位符替换 |
| 规则配置 | `engine/rule_config.dart` | RuleConfig 数据模型（fromJson） |
| 规则加载 | `engine/rule_loader.dart` | 从 JSON/文件/目录加载规则 |
| 规则执行 | `engine/rule_executor.dart` | 搜索/详情/歌词/歌单流程 |
| 响应处理 | `engine/response_handler.dart` | 列表提取、字段提取、分页 |
| 规则源 | `rule_based_source.dart` | MusicSource 实现，组装全流程 |
| 插件下载 | `adapters/plugin_manager.dart` | 下载/加载/适配 lx/mf 插件 |
| MusicFree 适配 | `adapters/plugin_manager.dart` | JSON → RuleConfig → RuleBasedSource |
| 落雪适配 | `adapters/plugin_manager.dart` | JS 格式识别（stub，JS 待支持） |

## core 新增源

- `LocalCustomSource`：自建歌曲（手动添加，SongDao 持久化）
- `FavoriteSource`：最喜欢（跨源收藏，FavoritesDao 持久化，回源获取详情）

## 测试结果

| 包 | 测试数 | 结果 |
| :--- | :--- | :--- |
| core | 27 | ✅ 全部通过 |
| expr | 50 | ✅ 全部通过 |
| crawler | 18 | ✅ 全部通过 |

## 项目结构更新

```
resonance/
├── resonance_app/
│   └── assets/
│       ├── rules/example.json    # 新增：示例规则文件
│       └── plugins/              # 插件下载目录
├── packages/
│   ├── core/                     # 新增 LocalCustomSource + FavoriteSource
│   ├── expr/                     # 不变
│   ├── crawler/                  # 新增：远程源实现
│   │   └── lib/src/
│   │       ├── http/             # HTTP 封装
│   │       ├── engine/           # 规则执行引擎
│   │       ├── adapters/         # 插件适配器
│   │       └── rule_based_source.dart
│   ├── player/                   # 不变
│   └── ui/                       # 待三期
```

## 完整 3 层架构

```
MusicSource 接口
├── 本地源组
│   ├── LocalScanSource    ✅ 一期
│   ├── LocalCustomSource  ✅ 二期
│   └── FavoriteSource     ✅ 二期
├── 规则引擎源
│   └── RuleBasedMusicSource  ✅ 二期
└── 插件适配器组
    ├── MusicFreeAdapter    ✅ 二期（基础）
    └── LxMusicAdapter      ✅ 二期（stub，JS 待支持）
```