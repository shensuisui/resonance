# resonance_app —— 回响 Resonance 壳工程

Flutter 壳工程，只做模块组装与服务注入，不写业务逻辑。
项目英文名 `resonance`，中文名「回响」。

## 命令

```bash
fvm flutter pub get    # 获取依赖
fvm flutter run        # 运行
fvm flutter analyze    # 静态分析
```

- 业务能力：`packages/core`（纯 Dart）、`packages/crawler`、`packages/player`、`packages/db`。
- UI：`packages/ui`（v1）与 `packages/uiv2`（v2，`lib/main_v2.dart` 入口）。
- 规则文件在 `assets/rules/`，第三方插件在 `assets/plugins/`，图标源在 `assets/icon/`。
- 仓库约定见根目录 [AGENTS.md](../AGENTS.md)。