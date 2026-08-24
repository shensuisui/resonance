# 第一期总结：基础设施

| 完成日期 | 2026-08-24 |
| :--- | :--- |
| 范围 | Step 1–8 |
| 涉及包 | core, expr, player |

---

## 完成步骤

| 步骤 | 文档 | 包 | 状态 |
| :--- | :--- | :--- | :--- |
| 1. 数据模型定义 | `docs/step1-data-models.md` | core | ✅ |
| 2. MusicSource 抽象接口 | `docs/step2-music-source.md` | core | ✅ |
| 3. 表达式解析器 + 执行器 | `docs/step3-expression-parser.md` | expr | ✅ |
| 4. 播放器抽象接口 | `docs/step4-player-interface.md` | core | ✅ |
| 5. 播放器实现 (just_audio) | `docs/step5-player-implementation.md` | player | ✅ |
| 6. 持久化层 | `docs/step6-persistence.md` | core | ✅ |
| 7. 本地文件源 | `docs/step7-local-source.md` | core | ✅ |
| 8. SourceManager 基础框架 | `docs/step8-source-manager.md` | core | ✅ |

## 包状态

### core（纯 Dart）
- 数据模型：Song, Album, Artist, Lyrics, Playlist, SearchResult, SourceInfo + 枚举
- MusicSource 抽象接口
- 本地源：LocalScanSource（扫描本地文件）
- 播放器接口：Player 纯 Dart 抽象
- 持久化层：DAO 接口 + 内存实现
- SourceManager：注册/启用/禁用/聚合搜索

### expr（纯 Dart）
- 解析器：CSSParser, JSONPathParser, XPathParser, RegexParser
- 执行器：CssEvaluator（html 包）, JsonPathEvaluator（json_path 包）, XPathEvaluator（xml 包）, RegexEvaluator（Dart SDK）
- ParserFactory 自动路由 + EvaluatorFactory 注册/执行
- 便捷方法：`evaluate(expression, data)`

### player（Flutter）
- PlayerImpl：基于 just_audio 的播放器实现
- 四种播放模式：列表循环/单曲循环/随机/顺序
- 播放队列、随机历史栈、状态流

## 测试结果

| 包 | 测试数 | 结果 |
| :--- | :--- | :--- |
| core | 19 | ✅ 全部通过 |
| expr | 50 | ✅ 全部通过 |

## 项目结构

```
fm/
├── .fvm/fvm_config.json          # FVM 3.47.1
├── fm_app/                       # 壳工程
│   └── assets/
│       ├── rules/                # 规则文件（空）
│       └── plugins/              # 插件文件（空）
├── packages/
│   ├── core/                     # 核心模块（纯 Dart）
│   │   └── lib/src/
│   │       ├── models/           # 9 个数据模型
│   │       ├── sources/          # MusicSource 接口 + LocalScanSource
│   │       ├── services/         # SourceManager
│   │       ├── player/           # Player 接口
│   │       └── db/               # DAO 接口 + 内存实现
│   ├── expr/                     # 表达式引擎（纯 Dart）
│   │   └── lib/src/
│   │       ├── parsers/          # 4 种解析器
│   │       ├── evaluators/       # 4 种执行器
│   │       └── expr_engine.dart  # 初始化 + 便捷方法
│   ├── player/                   # 播放器实现（Flutter）
│   │   └── lib/src/
│   │       └── player_impl.dart  # just_audio 封装
│   └── ui/                       # UI 模块（Flutter，待二期）
├── docs/                         # 8 步文档 + PRD
├── AGENTS.md
└── .gitignore
```

## 依赖关系

```
fm_app → ui → core + player
player → core
crawler → core + expr    # 二期
```

## 待二期开发

- 规则执行引擎（RuleExecutor, ResponseHandler）— crawler
- HTTP 请求封装 — crawler
- RuleBasedMusicSource — crawler
- 在线规则源（至少一个）
- 插件适配器（落雪、MusicFree）
- Riverpod 状态管理 + UI 页面
- 下载缓存