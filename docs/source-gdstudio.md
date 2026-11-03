# GD音乐台规则源（gdstudio_netease）

| 项 | 值 |
| :--- | :--- |
| 规则文件 | `fm_app/assets/rules/gdstudio_netease.json` |
| 源 ID / 名称 | `gdstudio_netease` / GD音乐台·网易云 |
| 接口文档 | https://music-api.gdstudio.xyz/api.php |
| 实测日期 | 2026-11-03 |
| 音乐库分栏 | 不占（`showInLibrary: false`，该接口没有歌单/推荐能力） |

## 1. 来源与合规

接口由 GD Studio 编写并发布，License 为 **CC BY-NC 4.0**，仅限学习参考、禁止商用。
规则源名称里保留「GD音乐台」即为注明出处；调用频率遵守站点限制
（**5 分钟内不超过 50 次请求**）。

## 2. 接口映射

一个接口用 `types` 区分四件事：

| types | 规则节点 | 参数 | 返回 |
| :--- | :--- | :--- | :--- |
| `search` | `search` | `source=netease`、`name`、`count`、`pages` | JSON 数组：`id`/`name`/`artist[]`/`album`/`pic_id`/`url_id`/`lyric_id`/`source` |
| `url` | `songDetail` 第 2 步 | `source`、`id`（曲目 ID）、`br` | `{url, br, size}` |
| `pic` | `songDetail` 第 1 步 | `source`、`id`（**专辑图 ID**）、`size` | `{url}` |
| `lyric` | `lyric` | `source`、`id`（曲目 ID） | `{lyric, tlyric}` |

## 3. 关键设计：复合 ID + 两跳详情

搜索接口只返回 `pic_id`（不给封面 URL），而播放/歌词要的是曲目 ID、封面要的是专辑图 ID。
因此：

* **搜索**把两个 ID 拼成复合 ID：`"id": "${$.id}~${$.pic_id}"`；
* **详情/歌词**用 `params` 表达式拆回来：
  `"id": "$.id && @Regex:^[^~]+"`、`"picId": "$.id && @Regex:[^~]+$"`；
* **详情两跳**：第 1 步取封面（`optional: true`，源侧给不出封面时跳过），第 2 步取播放地址。
  必需步骤失败照旧抛出，**不会假装有地址**。

> 音质由规则文件里的 `br` 决定（当前 `999` 无损）：可选 128 / 192 / 320 / 740 / 999。
> 实测 `br=999` 返回 FLAC（实际 br=1497，单曲约 21MB）。

## 4. 歌词双语

```json
"lyric": {
  "url": "/api.php?types=lyric&source=netease&id={id}",
  "params": { "id": "$.id && @Regex:^[^~]+" },
  "contentRule": "$.lyric",
  "translationRule": "$.tlyric",
  "translationJoin": " / "
}
```

引擎把译文按**时间戳对齐**并进同一行：`[00:23.929]塞纳河畔 左岸的咖啡 / ...`；
译文为空（多数中文曲目）时原样返回原文，行为与"不配译文"完全一致。

## 5. 平台可用性（2026-11-03 实测）

| source | 搜索 | 播放地址 | 歌词 |
| :--- | :--- | :--- | :--- |
| **netease** | ✅ | ✅ | ✅ |
| joox | ✅ | ❌ 返回空 url（br=-1） | ✅ |
| bilibili | ❌ 返回 `[]` | — | — |
| tencent / kuwo / tidal / qobuz / apple / ytmusic / spotify | ❌ HTTP 400 `Value of source is not supported` | — | — |

所以本规则源只做 netease；后续某个平台恢复时，按同一模板加一份规则文件即可
（每个规则文件 = 一个源，`source` 参数写死在 URL 里）。

## 6. 已知限制

1. **列表首次浏览没有封面**：搜索接口只给 `pic_id`，拿封面必须再请求一次 `types=pic`。
   封面在**播放或打开详情**时随详情一起取回，由 uiv2 的元数据服务落库，之后各页面统一回落显示
   （与 6U / 歌曲宝 现状一致）。
2. **多艺人只显示首位**：`artist` 是数组，引擎多值字段取首个元素。
3. **搜索不返回时长** → 列表显示 `0:00`，播放后由播放器实测时长回写。
4. **没有歌单/推荐接口** → 不占音乐库分栏，也不参与歌单发现页。
5. **播放地址带时效**（URL 内含时间戳，约 20 分钟），App 每次播放前现取，正常使用不受影响。
6. **限流 50 次 / 5 分钟**：一次搜索 1 次、一首歌播放 2 次（封面 + 地址）、歌词 1 次。

## 7. 验证方式

| 层次 | 文件 | 覆盖 |
| :--- | :--- | :--- |
| 引擎单测（HTTP 桩） | `packages/crawler/test/engine_params_test.dart` | 复合 ID 拆分进请求、可选步骤失败不毁播放、单请求详情同样支持 params、译文合并 |
| 纯函数单测 | `packages/crawler/test/lyric_merge_test.dart` | 时间戳对齐、缺译、脏数据、多时间戳行、厘秒换算 |
| 真实 API 测试 | `packages/crawler/test/gdstudio_test.dart` | 搜索 / 分页 / CDN 直链 / 封面 URL / 单语歌词 / 双语合并（真实网络，无 mock） |

```bash
cd packages/crawler
../../.fvm/flutter_sdk/bin/flutter.bat test --no-pub test/gdstudio_test.dart
```
