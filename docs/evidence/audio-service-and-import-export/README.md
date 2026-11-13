# 证据：AudioService 集成 + 数据导入导出

- 日期：2026-11-12
- 配套文档：`docs/features/mobile-audioservice.md`、`docs/features/data-import-export.md`

## 采集方式

本机无 adb/安卓设备（同 `docs/evidence/android-ux-fixes` 口径）。证据由**真实页面/真实组件**在 widget 测试渲染环境中采集：

- before-* ：完整 App（真实路由 appRouterProvider + 真实 DAO InMemoryDatabaseProvider + 真实字体 Manrope/Space Grotesk + 中文回退 Noto Sans SC）+ 用户造数（3 个歌单 / 1 收藏 / 3 最近 / 设置键）；
- preview-* ：真实设计令牌（UiV2DesignTheme 暗色）、真实组件（UiV2Section/UiV2Panel/UiV2ListRow/UiV2Button/UiV2Chip/UiV2GhostMini）与真实字体，背景为方案稿内容。

截图经 golden 输出（`flutter test --update-goldens`，`packages/uiv2/test/_evidence_shots_test.dart`）。**像素值可信，非 mock 假数据。**

## 对照

| 场景 | 图 |
|---|---|
| 现状：设置页（手机 390 宽整页）——可见无任何导入/导出入口 | 1-before-settings-phone.png |
| 现状：设置页（桌面 1280 宽）| 2-before-settings-desktop.png |
| 方案：设置页「数据备份」区块（变体 A 独立区块 / 变体 B 并入数据）| 3-preview-data-section.png |
| 方案：歌单详情页「导出」底部面板 | 4-preview-export-sheet.png |
| 方案：Android 13+ 媒体通知样式预览（audio_service 接入后的系统渲染）| 5-preview-media-notification.png |
| **实现后**：设置页「数据备份」区块（真实页面 + 真实数据 + 真实字体）| 6-after-settings-backup.png |
| **实现后**：导入备份预览弹层（合并/覆盖 + 分区勾选 + 逐项统计）| 7-after-import-preview.png |

## 说明

- 媒体通知由 Android 系统渲染，这里仅用真实字体与令牌预览**文案与按钮集合**（折叠/展开两种形态），实际样式以系统为准。
- before 中的造数仅用于让列表/计数非空，用于说明「数据在、却没地方导」；真实集合在设备上有多少不改变方案结论。
