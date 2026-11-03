# 打包与产物下载

仓库通过 GitHub Actions 工作流 [`.github/workflows/build.yml`](../.github/workflows/build.yml) 自动打包，参考 FlClash / mihon 的做法。

## 触发时机

| 触发 | 产物 |
| --- | --- |
| push 到 `master` | Android APK（按 ABI 拆分）+ Windows zip，作为工件保留 14 天 |
| Pull Request | 同上，方便在合并前下载测试 |
| 手动触发（Actions → Build → Run workflow） | 同上 |
| 推送 `v*` 标签（如 `v1.0.0`） | 同上，并额外创建 GitHub Release 挂载全部产物 |

## 下载方式

1. 打开仓库的 **Actions** 页，选择一次成功的 **Build** 运行。
2. 在页面底部的 **Artifacts** 区下载：
   - `resonance-android-apks`：`app-arm64-v8a-release.apk` 等按 ABI 拆分的安装包（测试分发，使用 debug 签名）。
   - `resonance-windows-x64`：解压后运行其中的 `fm_app.exe`。
3. 标签版本则在 **Releases** 页直接下载。

## 说明

- Flutter 版本取自根目录 `.fvmrc`，与本地 fvm 开发保持一致。
- Android release 目前使用 debug 签名（见 `fm_app/android/app/build.gradle.kts` 的 TODO），仅供测试；正式发布需另行配置签名。
- Android：`packages/crawler` 的 `flutter_inappwebview` 使用 `6.2.0-beta.3`——AGP 9 移除了 `getDefaultProguardFile('proguard-android.txt')`，稳定版 6.1.5 的 release 构建会直接失败；上游发布稳定版后可切回正式版。
- Android：`fm_app/android/build.gradle.kts` 会把插件子工程的 `compileSdk` 抬到 36——`audiotags` 1.4.5 写死 compileSdk 31，其 AndroidX 依赖要求 34+。
- Windows：工作流会先预解包 audiotags 插件自带的 Windows 原生库——该插件用 `cmake -E tar` 在自己的插件目录里解包，而插件目录经符号链接访问时 cmake 会拒绝解包。
- iOS / macOS / Linux / Web 暂未纳入打包，需要时再扩展。
