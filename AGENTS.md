# AGENTS.md — resonance

音乐播放 App，Flutter 项目，多模块架构。

## 项目结构

```
resonance/                    # 仓库根目录
├── .fvmrc                    # Flutter 版本锁定（3.47.9）
├── .fvm/flutter_sdk/         # 仓库内 Flutter SDK（本机直接使用）
├── resonance_app/            # 壳工程（Flutter App），无业务逻辑
│   └── assets/
│       ├── rules/            # 自有规则文件（.json）
│       └── plugins/          # 第三方插件文件
├── packages/
│   ├── core/                 # 核心模块（纯 Dart，零运行时依赖）
│   ├── expr/                 # 表达式解析（纯 Dart；依赖 html/xml/json_path）
│   ├── crawler/              # 远程源/规则引擎（Flutter 包；依赖 core+expr）
│   ├── player/               # 播放器实现（Flutter 包；依赖 core）
│   ├── db/                   # SQLite 持久化（Flutter 包；依赖 core）
│   ├── ui/                   # v1 UI（Flutter；已废弃，保留）
│   └── uiv2/                 # 现役 UI（Flutter）
├── demo_source/              # 开发用演示曲库 HTTP 服务（Dart）
├── docs/                     # 文档（入口见 docs/README.md）
├── AGENTS.md
└── .gitignore
```

## 模块依赖关系

```
resonance_app → uiv2（现役）/ ui（v1，已废弃）
uiv2 / ui → core + player + crawler + db
crawler → core + expr
player → core
db → core
```

## 开发命令

首选 fvm；本机 fvm 不可用（报 Git is not installed）时直接用仓库内 SDK：

```bash
fvm flutter pub get
fvm flutter run
fvm flutter build apk
fvm flutter build windows
fvm dart analyze
```

```powershell
# 本机兜底（Windows）
.fvm/flutter_sdk/bin/flutter.bat pub get
.fvm/flutter_sdk/bin/flutter.bat run
.fvm/flutter_sdk/bin/flutter.bat build apk
.fvm/flutter_sdk/bin/flutter.bat build windows
.fvm/flutter_sdk/bin/dart.bat analyze
```

## 测试

- 单包：在 `packages/<pkg>` 下 `flutter test`；纯 Dart 包（core/expr）用 `dart test`。
- 全部：`dart tool/test_all.dart`（跨平台；自动发现所有含 pubspec 的模块、按包类型选 runner、汇总结果，任一失败退出码 1）。
- 本机注意：`flutter`/`dart` 不在 PATH，实际用 `.fvm/flutter_sdk/bin/flutter.bat` / `.fvm/flutter_sdk/bin/dart.bat`（如 `.fvm/flutter_sdk/bin/dart.bat tool/test_all.dart`）。
- 覆盖率：各包 `flutter test --coverage`（当前未设统一门槛）。
- 本机跑 db / resonance_app 测试若触发 sqlite3 原生库下载，需代理：`HTTPS_PROXY=http://127.0.0.1:7890`（hook 用 `HttpClient.findProxyFromEnvironment`）。

## 约定

- 壳工程 `resonance_app` 只做模块组装，不写业务逻辑。
- 业务能力放在 `packages/core`（纯 Dart，无 Flutter 依赖）。
- 现役 UI 为 `packages/uiv2`；`packages/ui` 为 v1、已废弃；以后新 UI 版本按 uiv2 语义命名（如 `uiv3`），不要再建 `ui_*`。
- 规则文件（JSON）放 `resonance_app/assets/rules/`，插件文件放 `resonance_app/assets/plugins/`。
- 文档先写，维护在 `docs/`（结构与索引见 `docs/README.md`）。

## 开发原则

### 文档先行

- 新功能先出文档，维护在 `docs/` 目录下。
- 文档覆盖：设计思路、接口定义、数据结构、使用方式。

### 测试先行

- 单元测试为重中之重，核心逻辑必须覆盖。
- 新增功能先写测试用例，再实现。
- 运行全部测试：`dart tool/test_all.dart`。

### 代码质量

- 方法控制在合理行数内，超大方法及时拆分。
- Widget 树超过一定复杂度时抽取为独立 Widget 或方法。
- 优先组合而非继承，优先纯函数而非可变状态。

### 注释完整

- 正常代码和单元测试均需写注释。
- 单元测试不写注释会导致后续无法维护——测试意图、边界条件、模拟数据来源必须写清楚。
- 公共 API 必须写 dartdoc 注释。
