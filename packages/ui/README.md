# ui — resonance UI（v1，已废弃）

> ⚠️ 本包为 v1 UI，**已废弃**：壳工程默认入口已切换为 packages/uiv2，本包保留在仓库但不再被引入。新界面开发请看 packages/uiv2。

## 历史职责（v1）
- Material 3 + 种子色主题；riverpod_generator 生成 provider；Material 路由。
- 页面：搜索 / 播放 / 最近播放 / 歌单 / 源管理 / 设置。
- 依赖 core / crawler / player / db；cached_network_image、file_picker、card_settings_ui。

## 测试
在 packages/ui 下运行 flutter test。
