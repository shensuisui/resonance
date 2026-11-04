# 安卓 UI 缺陷修复证据（Issue #5）

对应 Issue：[缺陷] 安卓端不完善（五项：联网、安全域、返回键、键盘遮挡、底部弹层动画）。

## 采集方式（重要）

当前环境没有可用的安卓真机/模拟器（无 adb），因此证据由**真实组件**在 widget
测试渲染环境中采集，用合成 `MediaQuery` 复现安卓 edge-to-edge 的系统区域：

- `before-*`：基线 master（a4d7e06）的真实渲染；
- `after-*`：本分支（`agent/fix-android-ux-defects-019bff026d5b`）的真实渲染；
- 红色半透明带 = 系统区域示意：顶部 24px 为状态栏（`MediaQuery.padding.top`），
  底部 280px 为软键盘（`MediaQuery.viewInsets.bottom`），与安卓 targetSdk 35
  强制 edge-to-edge 后系统上报的值同构；
- 同一 harness、同一视口（顶栏 390×140，弹层 390×844）、同一深色主题、同一
  文案与内容，仅替换代码版本。截图用 `matchesGoldenFile` 输出（`--update-goldens`）。

未覆盖：真机上的网络连通性（第 1 条）为 AndroidManifest 权限声明，无法用截图
表达，由清单 diff 说明；系统返回键行为（第 3 条）为交互行为，由
`packages/uiv2/test/back_button_test.dart` 的 4 条 widget 测试覆盖。

## 对照

| 场景 | before | after |
| --- | --- | --- |
| 状态栏与标题栏：红带压住标题「Home」与右侧图标 | `before-topbar_statusbar.png` | `after-topbar_statusbar.png` |
| 键盘遮挡：新建歌单弹层落在红色键盘区内、表单被盖住 | `before-sheet_keyboard.png` | `after-sheet_keyboard.png` |
| 入场动效：整页（含蒙层）一起上滑 vs 蒙层全屏渐显 + 面板滑入 | `before-sheet_enter.png` | `after-sheet_enter.png` |
| 拖拽跟手：拖头部 200px 面板纹丝不动 vs 面板跟手下移 | `before-sheet_drag.png` | `after-sheet_drag.png` |