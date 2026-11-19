# 离线缓存升级「甲」——边播边落盘（1 倍流量）

> 状态：**已落地（2026-11-19）：采用 just_audio `LockCachingAudioSource`；M4 emulator 实测通过（served=2722=size、requests=1、缓存完整、seek 可用）** ｜ 更新：2026-11-19 ｜ 对应 offline-cache.md §五「预留」与下载功能 B 侧。

## 1. 背景

当前采用「乙」方案：起播后**后台另下一份**到缓存。成本是**双倍流量**。「甲」方案改为**播的就是缓存那份**：播放时边转发边落盘，完整后命中，1 倍流量且立即生效。

## 2. 现状代码面（已核实）

- `PlayerImpl.setAudioSource` 用 `AudioSource.uri` 直接播放，**没有**可替换的 `audioSourceBuilder`（offline-cache §五说预留，实际未实现）。
- `urlResolver` 仅无 url 时回调取 URL，不涉及 source 构建。
- `just_audio` 已依赖；`StreamAudioSource` 平台支持：Windows AIOM、Android ExoPlayer；**移动后台保活时流式 source 稳定性需实测**。

## 3. 方案（分层，可回退）

### M1：player 加 audioSourceBuilder（核心、零行为变化）——**已实现**

    typedef AudioSourceBuilder = AudioSource Function(Uri url, {required bool cache});
    PlayerImpl(audioSourceBuilder: ...) // 默认 = (url) => AudioSource.uri(url)

- 默认 `AudioSource.uri` = v1，全量测试守护无行为变化。
- 壳层注入「甲」builder：命中完整缓存 → 本地 file:// uri；未命中 → 流式转发源。

### M2：命中缓存直放

- 甲 builder 命中 `AudioCache` 完整文件 → 直接 `AudioSource.uri(file://)`，避免双下。未命中 → 走 v1。先拿到缓存命中收益与桌面验证。

### M3：实现方式调整 —— **弃用自建 tee，改用 just_audio 内置 `LockCachingAudioSource`**（`cacheFile` 指向 AudioCache 目标路径，完成后 `adoptExistingFile` 入索引）

    class CacheStreamAudioSource extends StreamAudioSource {
      // 输入：远端 Stream(List<int>)；旁路写 .part；
      // 完成无错 → rename 成完整文件 + 登记缓存；失败 → 删 .part，回退 v1 重播。
    }

- 失败回退：转发出错 → 回到 `AudioSource.uri(原始URL)` 重播（推荐）。
- 保持「乙」可恢复性：完整才改名，半截不播；目录/命名/命中/清理复用「乙」实现。

### M4：验收 —— **通过**（emulator-5554 集成测试 `cache_lock_e2e_test`：流量 1 倍 2722/2722、requests=1、缓存文件完整、seek 可用）

- seek / 进度 / 后台保活的流式 source 边界处理；release_check 冒烟。

## 4. 风险

| 项 | 影响 | 缓解 |
| --- | --- | --- |
| player 包加字段 | 低 | 默认行为不变 + 全量测试 |
| 壳层注入 builder 依赖 AudioCache 语义 | 中 | 命中/转发/回退收敛到 builder |
| StreamAudioSource 平台支持度 | 高 | 真机/桌面实测，移动后台尤其要验 |
| 边播缓存 duration/seek 一致性 | 中 | .part 保险 + M4 边界 |

## 5. 验收

1. 播未缓存新歌流量 ≈ 1 倍（对比乙 2 倍），播完已写缓存。
2. 断网后再播同一首已缓存：播放器一次都不请求源。
3. 播放中断网：已完成 → 恢复播放；否则留残片可重播/回退源。
4. 关开关 / 已下载的歌与 v1 完全一致。
5. Windows + Android 低延迟、无卡顿、seek 可用。

## 6. 决策点（待拍板）

| # | 问题 | 选项 |
| --- | --- | --- |
| 1 | 是否现在实施甲 | 只做 M1+M2（模式切换+命中直放）/ 全部 M1-M4 / 暂缓 |
| 2 | 流式转发失败回退 | AudioSource.uri(原URL) 重播（推荐）/ 直接失败 |
| 3 | 平台范围 | 先 Windows + Android 关键验证 / 全部 |
