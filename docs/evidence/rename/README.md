# 项目更名 resonance / 回响 + 默认界面接入 uiv2 —— UI 前后对比证据

本目录存放 PR #4「项目更名 + 默认界面接入 uiv2」的 UI 前后对比截图。

| 文件 | 内容 | 构建基线 |
|---|---|---|
| `before-fm_app-v1-about.png` | 更名前（v1 界面，已废弃）：Windows 窗口标题 `fm_app`；设置 → 关于 显示「FM 音乐」 | 提交 `3b23d6b`（更名前 PR 头；与 `9ebb9bc` 的 Dart/UI 代码相同，差异仅 Android compileSdk 与 pubspec.lock） |
| `after-resonance-v2-home.png` | 更名 + 接入 uiv2 后：窗口标题「回响」，默认入口 `lib/main.dart` 即 uiv2「回响 Resonance」深色界面（首页） | 本次提交（`main_v2.dart → main.dart`，壳工程不再引入 ui 包） |
| `after-resonance-v2-profile.png` | 同上，uiv2「我的」页（播放与外观 / 音乐源与订阅） | 同上 |

## 取证方式

- 平台：Windows 桌面 debug 构建，`flutter build windows --debug` 后直接运行 `runner\Debug\resonance_app.exe`。
- 场景/视口/状态一致：窗口 1280×720 置于 (20,20)；Before 为浅色主题 v1 界面（默认入口），After 为 uiv2 深色界面（默认入口即 `lib/main.dart`）。
- 截图均通过 `PrintWindow` 从应用窗口直接抓取（未受其他窗口遮挡影响）。
- 验证：更名前/后窗口标题由 `fm_app` 变为「回响」，默认界面由 v1（packages/ui）切换为 uiv2；`flutter analyze` 0 error / 0 warning，Windows 构建成功。

## v1（packages/ui）处置

- v1 界面已废弃：壳工程 `pubspec.yaml` 移除 `ui` 依赖，默认入口 `lib/main.dart` 直接使用 uiv2。
- 依赖 ui 的 v1 冒烟/布局集成测试（`ui_smoke_test.dart`、`ui_layout_scan_test.dart`）随 v1 一并移除。
- `packages/ui` 包保留在仓库中，但壳工程不再引入。
