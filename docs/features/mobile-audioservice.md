# 移动端 uiv2 集成 AudioService —— 调研与接入方案

> 结论速览：推荐 **audio_service 0.18.x**，用「controller 外包 + 通知由原生 service 渲染」的混合架构接入 `PlayerImpl`，接口侧零破坏、移动端零改造。详见第 5 节。

- 日期：2026-11-12
- 模块：`packages/player`（改造点）、`packages/uiv2`（无改动）、`resonance_app`（平台配置）
- 关联现状：`docs/summaries/summary-s1-s3.md` 中标记为「低优先级、未实现」的 S3-2
- 实施现状（2026-11-13 校准）：Android 后台播放已接线且配置齐全；iOS 仅初始化 handler，Info.plist 缺 UIBackgroundModes，暂不可用。详见 §9。

---

## 1. 调研时现状：uiv2 当时没有任何后台播放能力

当前播放链路是纯前台的：

| 层 | 实现 | 位置 |
|---|---|---|
| 播放器实现 | `PlayerImpl`（基于 just_audio 0.10.6，**单一 AudioPlayer**） | `packages/player/lib/src/player_impl.dart` |
| 播放器契约 | 纯 Dart 抽象 `Player` / `CurrentSongSource` / `AudibleSongSource` | `packages/core` |
| UI 绑定 | `playerStreamBindingProvider` 把三条流灌进 Riverpod | `packages/uiv2/lib/src/providers/providers.dart:1657` |
| 平台 | Windows 桌面为主；uiv2 交付文档未覆盖安卓真机后台 | `docs/ui/uiv2-delivery.md` |

**缺口（真实用户影响）：** App 切后台或熄屏后没有媒体通知、锁屏控制、耳机媒体键与 Android Auto；iOS 无 Control Center/灵动岛；安卓进程被杀后「后台播放」也随之停止。

```
docs/summaries/summary-s1-s3.md:63   S3-2 后台播放/锁屏/通知栏（可选，未实现）
docs/summaries/summary-s1-s3.md:113  低 | S3-2 后台播放/锁屏/通知栏 | 需 audio_service，平台特定
```

---

## 2. 三方库现状（实测 pub.dev，2026-11-12）

### 2.1 audio_service（主推）

| 项 | 值 |
|---|---|
| 最新版本 | **0.18.19**（2026-06-29 发布，仍在活跃迭代） |
| 周下载 | ~34 万（[pub.dev/packages/audio_service](https://pub.dev/packages/audio_service)） |
| 平台 | Android / iOS / macOS / Web（Windows 无原生实现） |
| 依赖 | rxdart、audio_session、flutter_cache_manager |

**能力：** 把任意音频引擎包装成可在后台运行的服务；统一提供媒体通知、锁屏控制、耳机媒体键、Android Auto、iOS Control Center / 灵动岛等接口。

### 2.2 just_audio_background（作者官方精简版）

| 项 | 值 |
|---|---|
| 最新版本 | **0.0.1-beta.17**（2025-05，仅 beta） |
| 周下载 | ~7.5 万 |
| 依赖 | 基于 audio_service 0.18.18 |

**定位（作者原话）：**「适合**单一 AudioPlayer 实例**的简单场景；需求更复杂请直接用 audio_service」。本项目 `PlayerImpl` 恰好是单一 `AudioPlayer`，但它把通知按钮/行为固化成「下一个/上一个/暂停」三件套，无法映射本项目由 `PlayMode` 决定的随机/循环切换，灵活性不足 → 不选。

### 2.3 flutter_media_session（后起之秀，先观望）

| 项 | 值 |
|---|---|
| 最新版本 | 3.1.0（2026-11-08） |
| 周下载 | pub likes 4 |
| 平台 | Android / iOS / macOS / **Windows** / Web —— 原生 SMTC |

**唯一同时覆盖 Windows SMTC 的选项**（SystemMediaTransportControls）。但生态权重低、无长期背书；且 Linux 的 MPRIS 仍未实现（README 标 Planned）。作为备选演进方向。

### 2.4 关键事实核对

- 仓库 `ryanheise/audio_service`：872★、未归档、最近 push 2026-07。
- `audio_service` 0.18.19 的 Android 清单（包内实测）只有 `<manifest/>`，**前台服务权限与 `service` 声明需要应用侧配置**（见第 6 节）。
- Android 侧 `startForeground` 直接调用，**没有**为 Android 14+ 传 `foregroundServiceType`（源码 `AudioService.java:727`），因此应用侧需在 `service` 上自行声明 `android:foregroundServiceType="mediaPlayback"` + 权限 `FOREGROUND_SERVICE_MEDIA_PLAYBACK`。
- `POST_NOTIFICATIONS`：Android 13+ 需运行时申请；`audio_service` 的 `init` 无自动弹窗。

---

## 3. 为什么不换引擎 / 不直接用 media_kit

- **不换引擎**：`just_audio` 已承载 `PlayerImpl` 的全部超时自愈、串行队列、进度回写逻辑（约 586 行，含多轮线上回归修复），换 `media_kit` 等于重写播放器并引入新的桌面/移动差异。
- **不需要二次开发**：`audio_service` 是社区事实标准，与现有 `just_audio` 生态同源，文档与例子充足，符合「先文档、测试先行」原则。

---

## 4. 接入目标与不做的事

**做：**
1. Android/iOS 后台播放、系统媒体通知、锁屏/通知栏控制、耳机媒体键、蓝牙耳机；
2. Android Auto / iOS 锁屏（audio_service 原生能力）；
3. 通知归属「回响」，点击回到 App 并保持当前队列。

**明确不做（一期）：**
- Windows SMTC：`audio_service` 无 Windows 实现，桌面端保持现状（可后续单独补）；
- Linux MPRIS 一期不接。

---

## 5. 目标架构（混合方案）

关键设计点：

1. **不改 `PlayerImpl` 本体**：新建一个适配器（如 `AudioBackgroundPlayer`）实现同一个 `Player` 接口，内部持有真实 `PlayerImpl` + `AudioHandler` 桥。壳工程 `main.dart` 里 `PlayerImpl(...)` 处换成这个适配器即可，`playerProvider` 仍是 `Player`，uiv2 与测试桩全部零改动。

2. **通知只做渲染层**：元数据（封面/标题/歌手/时长）与进度通过 controller 从真实播放器推给 `AudioHandler.updateMediaItem`；按钮行为（播放/暂停/上一个/下一个）在 `AudioHandler` 里映射到 `PlayerImpl` 的现有方法，不复制播放逻辑。

3. **随机/循环可控**：自定义 `MediaControl` 集合，把 `PlayMode` 拉到通知里（随机/循环切换仍走 `PlayerImpl.playMode` setter），避免 just_audio_background 三件套的短板。

---

## 6. Android 平台配置（0.18.19 实测结论）

`AndroidManifest.xml` 需补充（`audio_service` 包自身 manifest 为空，见 2.4）：

```xml
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>

<service android:name="com.ryanheise.audioservice.AudioService"
    android:exported="true"
    android:foregroundServiceType="mediaPlayback"
    tools:ignore="Instantiatable">
  <intent-filter><action android:name="android.media.browse.MediaBrowserService"/></intent-filter>
</service>
<receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
    android:exported="true" tools:ignore="Instantiatable">
  <intent-filter><action android:name="android.intent.action.MEDIA_BUTTON"/></intent-filter>
</receiver>
```

- `FOREGROUND_SERVICE_MEDIA_PLAYBACK`：targetSdk 34+ 必加，否则会抛 `SecurityException`。
- `android:foregroundServiceType="mediaPlayback"`：0.18.19 未自动注入，补齐后通知能正确归类为媒体。
- iOS：需在 `Info.plist` 加 `UIBackgroundModes` 的 `audio`（**当前尚未添加，iOS 后台播放暂不可用**）。
- 通知图标：`resonance_app/android/app/src/main/res/drawable*/ic_stat_*.png`（**当前未配置，使用系统默认图标**）。

---

## 7. 风险与取舍

| 风险 | 影响 | 缓解 |
|---|---|---|
| `audio_service` 无 Windows 实现 | 桌面端拿不到后台/通知 | 一期不做桌面；Windows SMTC 另用 `flutter_media_session` 演进 |
| 通知按钮与 playback 状态不同步 | 常规坑 | 以 `PlayerImpl.stateStream` 为唯一事实源，通知只在桥接层刷新 |
| Android 13+ 通知权限 | 首次启动无提示会丢通知 | 在「允许通知」流程里统一申请（可关，不影响播放） |
| 多 Player 支持 | audio_service 只支持单 handler | 本项目正好就是单 Player |
| 换引擎破坏现有进度/超时逻辑 | 回归风险 | 适配器不改 `PlayerImpl`，仅壳层替换；跑全量测试 + Android 模拟器冒烟 |

---

## 8. 实施步骤（小步，边界清晰）

1. `player` 包加依赖 `audio_service: ^0.18.19` + `audio_session`；
2. 写 `AudioBackgroundPlayer implements Player, CurrentSongSource, AudibleSongSource`（内部组合 `PlayerImpl`）；
3. 写 `AudioHandler extends BaseAudioHandler` 做命令/元数据桥；
4. Android 清单 + iOS plist + 通知图标配置；
5. `main.dart` 把 `PlayerImpl` 替换为 `AudioBackgroundPlayer`，`init()` 里 `AudioService.init(...)`；
6. 测试：`Player` 契约的现有 uiv2 widget 测试应全绿（接口不变）；`audio_service` 的集成层加薄壳单测；
7. 真机/模拟器验证：切后台仍出声、通知可控制、锁屏可 seek、耳机媒体键有效。

> 交付物：本方案经批准后按「先文档后实现」，新增能力文档放 `docs/`；实施前先补「Android 模拟器后台播放」验证用例。

---

## 9. 实施记录（2026-11-12，一期：仅 Android）

**已完成**
- `packages/player/lib/src/audio_handler.dart`：新增 `ResonanceAudioHandler`（BaseAudioHandler 子类）+
  `AudioBackground.init`。**采用「侧车」而非「适配器」**：不实现 20+ 个 Player 成员转发，只观察
  `stateStream / positionStream / durationStream / currentSongStream` 并把命令转回 PlayerImpl，
  PlayerImpl 一行未改（桌面行为零变化）。
- 通知按钮：上一首 / 播放-暂停 / 下一首；`systemActions` 含 seek；`repeatMode/shuffleMode` 由
  `PlayMode` 映射（repeatMode：listLoop→all、singleLoop→one、shuffle→none、sequential→none；shuffleMode：shuffle→all，其余→none）。
- `resonance_app/lib/main.dart`：仅 Android/iOS 初始化媒体服务，失败只记日志、不影响前台播放。
- Android：清单补 WAKE_LOCK / FOREGROUND_SERVICE / FOREGROUND_SERVICE_MEDIA_PLAYBACK /
  POST_NOTIFICATIONS，新增 `AudioService` 服务（`foregroundServiceType="mediaPlayback"`）与
  `MediaButtonReceiver`；`MainActivity` 改为继承 `AudioServiceActivity`。

**测试**
- 新增 `packages/player/test/audio_handler_test.dart`：20 项（状态映射、曲目/队列去重广播、
  命令转发、越界忽略、点播重建、repeat/shuffle 写回）。`player` 包 analyze 0 issue。

**未完成 / 需要真机验证**
- ~~本机 Gradle 构建卡在 sqlite3 下载~~ **已解决**（2026-11-13：`file_picker` 固定 10.3.10 + `HTTPS_PROXY` 代理后，`flutter build apk --debug` 成功，见 features/build.md）。
- 「通知实际样式/锁屏/耳机键/后台保活」仍需真机/模拟器实测（2026-11-19 起可用模拟器 + APK 验证,见验证记录处）。
- 自定义通知按钮（随机/循环图标）未做：需要自备两枚 drawable；一期先用系统 repeat/shuffle 状态字段。
