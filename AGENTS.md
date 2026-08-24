# AGENTS.md — fm

音乐播放 App，Flutter 项目，多模块架构。

## 项目结构

```
fm/                          # 仓库根目录
├── .fvm/
│   └── fvm_config.json      # FVM 版本锁定 3.47.1
├── fm_app/                  # 壳工程（Flutter App），无业务逻辑
│   └── assets/
│       ├── rules/            # 自有规则文件（.json）
│       └── plugins/          # 第三方插件文件
├── packages/
│   ├── core/                # 核心模块（Dart package）
│   │   ├── lib/src/core_base.dart
│   │   └── lib/core.dart
│   ├── expr/                # 表达式解析抽象层（Dart package）
│   ├── crawler/             # 远程源实现（Dart package），依赖 core + expr
│   ├── player/              # 播放器实现（Flutter package），依赖 core
│   └── ui/                  # UI 模块（Flutter package），依赖 core + crawler + player
├── docs/
│   └── prd.md               # 产品需求文档
├── AGENTS.md
└── .gitignore
```

## 模块依赖关系

```
fm_app → ui
ui → core + player + crawler
crawler → core + expr
player → core
```

## 开发命令

所有 Flutter/Dart 命令通过 `fvm` 执行：

```bash
fvm flutter pub get                    # 获取依赖
fvm flutter run                        # 运行
fvm flutter build apk                  # 构建 Android
fvm flutter build windows              # 构建 Windows
fvm dart analyze                       # 静态分析
fvm dart test                          # 运行测试
```

## 约定

- 壳工程 `fm_app` 只做模块组装，不写业务逻辑。
- 业务能力放在 `packages/core`（纯 Dart，无 Flutter 依赖）。
- UI 相关放在 `packages/ui`（Flutter package，依赖 core）。
- 未来新增 UI 版本以 `packages/ui_*` 命名。
- 规则文件（JSON）放在 `fm_app/assets/rules/`，插件文件放在 `fm_app/assets/plugins/`。

## 开发原则

### 文档先行

- 新功能先出文档，维护在 `docs/` 目录下。
- 文档覆盖：设计思路、接口定义、数据结构、使用方式。

### 测试先行

- 单元测试为重中之重，核心逻辑必须覆盖。
- 新增功能先写测试用例，再实现。
- 运行全部测试：`fvm dart test`

### 代码质量

- 方法控制在合理行数内，超大方法及时拆分。
- Widget 树超过一定复杂度时抽取为独立 Widget 或方法。
- 优先组合而非继承，优先纯函数而非可变状态。

### 注释完整

- 正常代码和单元测试均需写注释。
- 单元测试不写注释会导致后续无法维护——测试意图、边界条件、模拟数据来源必须写清楚。
- 公共 API 必须写 dartdoc 注释。