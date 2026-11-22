# 车载歌词（蓝牙标题注入）

> 状态：已实现（Dart 侧测试通过；**Android/iOS 原生未在本机编译/真机验证**）

## 1. 背景与原理

蓝牙媒体走 **AVRCP**，车机只能拿到标准属性：**TITLE / ARTIST / ALBUM / 曲目号 / 总曲目数 / 流派 / 时长**（另加封面句柄），**没有歌词字段**（BlueZ `avrcp.c` 属性表可证；Android `MediaMetadata` 也无 `METADATA_KEY_LYRICS`）。

因此“车机显示歌词”的实现方式是把**当前歌词行写进 TITLE（或 ARTIST）**，让车机在对应行显示。是否可见取决于车机是否持续刷新该字段——很多车机只在切歌时读取并缓存，则不会滚动。

**iOS 侧**：`MPMediaItemPropertyLyrics` 不参与正在播放展示（SO 实证 “You cannot set lyrics”），但 **title 可自由修改**，故同一套路可用；限制是 iOS `nowPlayingInfo` 更新有延迟/偶发丢更新，需要写入后校验重试。

## 2. 配置（设备本地，不同步）

| 键 | 取值 | 默认 | 文案 |
|---|---|---|---|
| `car_lyrics_scope` | `off` / `car` / `all` | `off` | 显示范围：关闭 / 仅车载 / 所有蓝牙 |
| `car_lyrics_slot` | `title` / `artist` | `title` | 歌词位置：第一行 / 第二行 |

## 3. 注入规则

- `off` → 不注入；
- 未连接蓝牙音频 → 不注入（避免通知栏/锁屏无故变歌词）；
- `car` 且未识别为车机 → 不注入；
- 当前无歌词行 → 不注入。
- 信息行统一 `歌手 - 歌名`：
  - `title` 槽：第一行 = 歌词，第二行 = `歌手 - 歌名`；
  - `artist` 槽：第一行 = `歌手 - 歌名`，第二行 = 歌词。
- 恢复：暂停 / 停止 / 切歌 / 断开蓝牙 / 关闭配置 → 还原真实 `歌名 / 歌手`。
- 去重：按最终元数据比较，同一行不重复推送；配置/连接变化会补推。

## 4. 车机判定

| 平台 | 依据 | 局限 |
|---|---|---|
| iOS | `AVAudioSession` 输出端口 `.carAudio` | 无蓝牙设备类；普通蓝牙车机与音箱无法区分（以 carAudio 为准，CarPlay/车载音频可识别） |
| Android | `BluetoothClass` 含 `AUDIO_VIDEO_CAR_AUDIO`（A2DP/HFP 已连接） | 车机不上报该类别时识别不到；需要 `BLUETOOTH_CONNECT`（API 31+） |

判定失败一律按“非车载”处理；`scope=all` 不受判定影响。

## 5. 代码位置

- `packages/core/lib/src/models/car_lyrics.dart`：枚举、`resolveCarLyricsMetadata`、`formatSongInfo`、`carLyricLineIndexAt`。
- `packages/uiv2/lib/src/components/car_lyrics_section.dart`：设置区块（三态 + 位置）。
- `packages/player/lib/src/car_lyrics_controller.dart`：行选择/节流/恢复；`audio_handler.dart` 的 `setMetadataOverride`。
- `resonance_app/lib/car_lyrics/car_lyrics_service.dart`：平台通道封装。
- `resonance_app/android/.../MainActivity.kt`、`resonance_app/ios/Runner/AppDelegate.swift`：原生判定。

## 6. 验证清单

**已通过（Dart）**
- core 18 项：范围矩阵 / 槽位映射 / 信息格式 / 行选择。
- uiv2 4 项：三态与位置切换、hint 文案。
- player 6 项：行切换去重、暂停恢复、切歌重置、off/未连蓝牙不注入、refresh 补推。
- app 3 项：状态解析与无实现降级。
- 全量 11 模块 0 失败；analyze 无 error。

**待真机（本机无法完成）**
1. Android：`flutter build apk --debug` 编译通过（本机未接受 Android licenses，未跑）。
2. Android 真机：开 `scope=all` 连任意蓝牙，`adb shell dumpsys media_session` 观察 metadata 的 title/artist 随歌词行变化；再连车机看屏幕。
3. iOS 真机：连车机/CarPlay，观察锁屏与车机；确认延迟时重试策略是否需要加强。
4. 车机兼容性：记录“会刷新 / 只读一次 / 不显示”的车型，必要时调整节流或槽位。

## 7. 已知限制

- 车机不刷新 TITLE/ARTIST → 功能不可见（车机限制，App 无法绕过）。
- 通知栏/锁屏会同步变歌词；仅蓝牙连接时启用可缓解。
- 单行显示车机在 `title` 槽下看不到歌名（信息行在第二行）。
