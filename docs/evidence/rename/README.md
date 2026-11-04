# 项目更名 resonance / 回响 —— UI 前后对比证据

本目录存放 PR #4「项目更名」提交（`fm_app` → `resonance_app`）的 UI 前后对比截图。

| 文件 | 内容 | 构建基线 |
|---|---|---|
| `before-fm_app-about.png` | 更名前：Windows 窗口标题 `fm_app`；设置 → 关于 显示「FM 音乐」 | 提交 `3b23d6b`（更名前 PR 头；与 `9ebb9bc` 的 Dart/UI 代码相同，差异仅 Android compileSdk 与 pubspec.lock） |
| `after-resonance-about.png` | 更名后：窗口标题「回响」；设置 → 关于 显示「回响」 | 更名提交（本地构建基于 `68626d9`，其 resonance_app/lib、windows、packages/ui 代码与当前 head `034ec5c` 相同） |

## 取证方式

- 平台：Windows 桌面 debug 构建，`flutter build windows --debug` 后直接运行 `runner\Debug\*.exe`。
- 场景/视口/状态完全一致：窗口 1280×720 置于 (20,20)，浅色主题，uiv1 界面（默认入口 `lib/main.dart`），导航 设置 → 关于 页。
- 截图均通过 `PrintWindow` 从应用窗口直接抓取（未受其他窗口遮挡影响）。
- 验证：更名前/后同一操作路径下，标题栏与「关于」页应用名同步变化；`flutter analyze` 0 error/0 warning，Windows 构建成功，PR CI 3/3 通过。
