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
   - `fm-android-apks`：`app-arm64-v8a-release.apk` 等按 ABI 拆分的安装包（测试分发，使用 debug 签名）。
   - `fm-windows-x64`：解压后运行其中的 `fm_app.exe`。
3. 标签版本则在 **Releases** 页直接下载。

## 说明

- Flutter 版本取自根目录 `.fvmrc`，与本地 fvm 开发保持一致。
- Android release 目前使用 debug 签名（见 `fm_app/android/app/build.gradle.kts` 的 TODO），仅供测试；正式发布需另行配置签名。
- iOS / macOS / Linux / Web 暂未纳入打包，需要时再扩展。
