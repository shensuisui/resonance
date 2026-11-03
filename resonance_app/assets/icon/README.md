# App 图标资产

| 文件 | 用途 |
|---|---|
| `app_icon.svg` | **形状的唯一事实来源**（纯矢量，1024 网格） |
| `app_icon.png` | 1024 满底版。iOS / Windows / Web / macOS / 旧版 Android |
| `app_icon_foreground.png` | 1024 透明底白标记。Android 自适应图标前景层（标记只占中间 56%，在 66% 安全区内） |

配色**只有两种**，与现有 logo 一致：

- 品牌红 `#C9341C`（= 浅色主题 accent）
- 白 `#FFFFFF`

形状：中心圆点 + 左右各一道向外的弧（弧宽 = 边长的 8.8%），语义为「回响 / 回声」。

## 改图标怎么做

1. 改 `app_icon.svg`（矢量源，别直接改 PNG）；
2. 重新导出 `app_icon.png` / `app_icon_foreground.png`（1024×1024）；
3. 在 `resonance_app` 下执行 `dart run flutter_launcher_icons` 刷新各平台产物；
4. `flutter test packages/uiv2/test/app_icon_asset_test.dart` 会校验尺寸与两种品牌色是否精确。

## 注意

- 这个目录**不要**登记到 `pubspec.yaml` 的 `assets:` 里 —— 它只给 `flutter_launcher_icons` 读，登记了会白占包体。
- Linux 不在 `flutter_launcher_icons` 支持范围内，桌面端图标需另行处理。
- Windows 的 `.ico` 目前是工具默认的**单张 256×256**（系统自己缩放到 16/32/48）；若觉得任务栏偏软，可以另外补一个多尺寸 ico，但要注意重跑工具会覆盖回单尺寸。
