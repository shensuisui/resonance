# uiv2 —— 「回响 Resonance」界面

`packages/uiv2` 是 fm 音乐播放器的第二套 UI 实现，按 OpenDesign 原型
（`index.html` + `assets/styles.css` + `assets/app.js`，项目 id `697ea853-0cd1-491b-971b-ae28a51ead33`）
逐条还原：同一套界面覆盖手机与大屏，深色优先，自带配色令牌、图标集与响应式断点。

## 与 ui（v1）的关系

| | ui（v1） | uiv2 |
|---|---|---|
| 视觉 | Material 3 + 种子色 | 原型自带令牌（深色 `#0C0E11` / 强调 `#FF5A3C`） |
| 状态 | riverpod_generator（需 build_runner） | 显式 `NotifierProvider`/`Provider`，无需代码生成 |
| 第三方依赖 | cached_network_image / card_settings_ui / file_picker / path_provider | 无（仅 flutter + flutter_riverpod + 仓库内包） |
| 导航 | Material 路由 + IndexedStack | 自有 hash 风格路由（`navProvider`），六个一级页保留状态 |
| 图标 | Material Icons | 原型 SVG sprite 逐条重建（`UiV2Icon`） |

两者都只依赖 `core` / `crawler` / `player` / `db`，壳工程按入口二选一。

## 规模

- 37 个 Dart 文件、约 11.3k 行（不含生成代码）；
- 16 个页面：首页、搜索、音乐库、我喜欢的音乐、本地音乐、我的、专辑、艺人、歌单、
  全部歌单、文件夹、最近播放、下载任务、音乐源、订阅、运行日志；
- 素材：16 张专辑封面（`fm_app/assets/covers/`）+ 两族可变字体
  （Manrope / Space Grotesk，`fm_app/assets/fonts/`）。

## 目录

```
lib/
├── uiv2.dart                  # 包导出清单
├── src/
│   ├── app.dart               # UiV2App（MaterialApp + 令牌作用域）
│   ├── router.dart            # 路由表 / 一级页口径 / 返回键规则
│   ├── design/                # tokens / typography / icons / theme / motion
│   ├── data/                  # catalog（16 张专辑配表）/ lyrics（演示歌词）
│   ├── providers/providers.dart  # 服务注入 + 播放 + 收藏 + 搜索 + 设置
│   ├── components/            # 外壳零件、播放条、沉浸页、曲目行、卡片、弹层
│   ├── widgets/               # 页面骨架、曲目动作
│   └── pages/                 # 16 个页面
```

## 断点（与原型 styles.css 一致）

| 宽度 | 侧栏 | 顶栏 | 底部导航 | 播放条 | 返回键 |
|---|---|---|---|---|---|
| < 768 | 隐藏 | 显示 | 显示（二级页收起） | 仅上一/播放/下一 + 顶部细线进度 | 顶栏 |
| 768–1023 | 88px 窄轨 | 隐藏 | 隐藏 | 一行三区 | 浮动键（88+16） |
| 768–1180 | 同上 | 隐藏 | 隐藏 | 平板口径：隐藏歌名与音量组 | 同上 |
| ≥ 1024 | 264px 完整 | 隐藏 | 隐藏 | 一行三区 | 侧栏品牌行 |
| ≥ 1440 | 264px | 隐藏 | 隐藏 | 一行三区 | 侧栏品牌行 |

## 使用

壳工程（`fm_app`）里注入五个服务 Provider 即可：

```dart
runApp(ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWith((ref) => gDatabaseProvider),
    sourceManagerProvider.overrideWith((ref) => gSourceManager),
    playerProvider.overrideWith((ref) => gPlayer),
    downloadManagerProvider.overrideWith((ref) => gDownloadManager),
    recentPlaysServiceProvider.overrideWith((ref) => gRecentPlaysService),
  ],
  child: const UiV2App(),
));
```

## 曲库与真实播放

- 曲库（专辑 / 曲目 / 歌单 / 分类）是**配表驱动的演示数据**，与原型一致；
- 播放统一走 `PlaybackController`：解析播放地址 → 调 `Player` → 同步 UI 状态 → 记录最近播放；
- 演示曲目在真实源里没有对应的播放地址，点击后不会启动播放，但界面状态（选中行、播放条信息、
  队列与最近播放）按原型语义正确更新；接入真实源（本地扫描 / 规则源 / 插件）后按同一入口播放真实音频。

## 测试与静态检查

> 本机沙箱下 `flutter.bat` 无法启动（批处理进程被拦截），因此下述命令需要在
> 普通终端里执行；本次交付的代码已用 analyzer 包做过全量类型检查：
> **37 个文件 0 error / 0 warning**。



```bash
# 本机 fvm 包装器不可用，直接用仓库内的 Flutter SDK
G:\works\shelli\fm\.fvm\flutter_sdk\bin\flutter.bat flutter pub get   # 在 packages/uiv2 下
\\.fvm\flutter_sdk\bin\flutter.bat analyze                             # 在 packages/uiv2 下
\\.fvm\flutter_sdk\bin\flutter.bat test                                # 在 packages/uiv2 下
```