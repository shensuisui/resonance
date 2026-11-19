# 离线缓存「甲」验收（LockCachingAudioSource，2026-11-19）

环境：Android 模拟器 emulator-5554；集成测试 `integration_test/cache_lock_e2e_test.dart`。

## 实测值
- 播放源时长约 0.6s 的真实 mp3（2722 字节）。
- 服务端记账：**served=2722，size=2722，requests=1** → 流量约 **1 倍**（对比「乙」的 2 倍）。
- 播放结束后 `AudioCache.isCached=true`，缓存文件长度 = 2722（完整）。
- `player.seek(300ms)` 可用，缓存不被破坏。
- **headers 路径**：LockCaching 带 `referer` 时经本机回环明文代理转发，服务端收到 `referer=https://ref.example/`（需 Android network security config 放行 127.0.0.1/localhost）。

## 复现
`flutter test integration_test/cache_lock_e2e_test.dart -d emulator-5554`（+1 通过）。
