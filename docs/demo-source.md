# 演示曲库 HTTP 源

## 目标

把原先内置在 App 里的演示曲库（专辑配表、歌词、封面、占位音频）移出 App，改成根目录下一个**仅开发调试使用**的独立 Dart HTTP 服务。

它同时承担两个职责：

1. 作为真实音乐源：App 通过普通规则源（`rule.json`）访问搜索、详情、歌词、歌单与播放地址；
2. 作为慢网络/异常调试台：所有数据接口都能通过 `d` 参数人为延迟返回。

正式发行版不注册该源，也不打包它的任何数据或静态资源。

## 目录

```text
demo_source/
├── bin/server.dart
├── lib/
│   ├── demo_server.dart       # 路由、延迟、响应
│   ├── demo_catalog.dart      # 演示数据模型与查询
│   ├── rule_template.dart     # 渲染 data/rule.json 的来源占位符
│   └── wav.dart               # 纯 Dart 生成 PCM WAV
├── data/
│   ├── catalog.json           # 专辑、曲目、歌单及来源归属
│   ├── lyrics.json            # 原创演示歌词
│   └── rule.json              # 可在 URL 里直接调 d= 秒数的规则模板
├── covers/                    # 从 App 移出的 16 张封面
└── test/
```

服务只依赖 Dart 标准库；测试使用 `package:test`。它不依赖 Flutter，也不被 App 的 pubspec 依赖。

## 启动

```powershell
cd demo_source
..\.fvm\flutter_sdk\bin\dart.bat pub get
..\.fvm\flutter_sdk\bin\dart.bat run bin/server.dart
```

默认监听 `0.0.0.0:8787`。参数：

```text
--host 0.0.0.0
--port 8787
--root <demo_source 目录>
```

监听 `0.0.0.0` 是为了让 Android 模拟器（`10.0.2.2`）和真机（局域网 IP）都能访问；服务本身仍只提供本地开发数据。

## 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/health` | 健康检查 |
| GET | `/rule.json` | 动态生成 App 使用的规则源 |
| GET | `/catalog.json` | UI 展示用目录快照 |
| GET | `/search?keyword=&page=1&pageSize=20&d=0` | 搜索；无关键词返回空 |
| GET | `/songs/{id}?d=0` | 曲目详情，含播放地址 |
| GET | `/lyrics/{id}?d=0` | LRC 歌词；无歌词返回 404 |
| GET | `/playlists?d=0` | 推荐歌单 |
| GET | `/playlists/{id}?d=0` | 歌单详情与歌曲 |
| GET/HEAD | `/covers/{file}` | 封面静态文件，支持 Range |
| GET/HEAD | `/audio/demo.wav` | 可播放 PCM WAV 流，支持 Range |

### 延迟参数

`d` = 当前请求在返回前等待的秒数，默认 0，最多 300，可写小数：

```text
/search?keyword=blue&d=10
/songs/midnights-3?d=0.5
```

非法或负数返回 400。延迟只作用于当前请求，不会隐式传染封面或音频。

### 规则源

曲目对外 id 使用 URL 安全形式（如 `midnights-3`）。旧配表里的 `midnights#3` 在 `#` 之后会被 HTTP 当作 fragment，服务端只会收到 `/songs/midnights`，因此服务在加载时统一把 `#` 归一化为 `-`；data 文件仍可保留原配表写法。

`/rule.json` 的 `baseUrl` 按本次请求的 `Host` 动态生成，不在文件里写死 IP。这样同一份规则可同时服务桌面（127.0.0.1）、Android 模拟器（10.0.2.2）和局域网真机。

规则源 id 固定为 `demo_catalog`，类型为 `rule`。所有真实数据能力都由 crawler 现有的规则执行器完成，不为演示源增加特例。

### 音频

默认使用纯 Dart 生成的 **16kHz / 单声道 / 16-bit / 30 秒 PCM WAV**，不提交音频二进制，不需要 ffmpeg。响应支持 `Range` 与 `HEAD`，便于播放器 seek。

WAV 是当前实现；若某平台实测播放异常，再切换为预生成 MP3，服务端路由不变。

## App 接入

仅 Debug 生效：

- 读取 `RESONANCE_DEMO_BASE_URL`（`--dart-define`），桌面默认 `http://127.0.0.1:8787`，Android 模拟器默认 `http://10.0.2.2:8787`；
- 请求 `/rule.json`，解析成现有 `RuleBasedMusicSource` 并注册；
- 请求 `/catalog.json`，注入 UI 的目录展示元数据；
- 服务不在线时记录明确警告并跳过，不阻塞 App 启动。

Release：

- 不在 `kDebugMode` 分支内，跳过全部演示源初始化；
- 演示数据、封面、音频均不在 Flutter assets 中，物理上不进安装包。

## 测试

```powershell
cd demo_source
..\.fvm\flutter_sdk\bin\dart.bat test
```

关键覆盖：

- 16 张专辑、190 首歌、7 个歌单、9 首歌词的完整性；
- 搜索命中、空关键词、分页；
- 曲目详情与真实播放地址；
- 延迟参数实际耗时与非法值；
- 封面/WAV 的 Content-Type、Content-Length、Range/206/416；
- 规则 JSON 的 baseUrl 按 Host 生成。

## Release 验证

构建 Release 后检查：

1. 安装包内不存在 `covers`、`demo_source`、演示歌词或目录配表；
2. 启动日志里没有演示源加载记录；
3. 搜索、音乐源列表中不出现 `demo_catalog`。
