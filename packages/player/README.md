# player — 播放器实现（just_audio）

实现 core 的 Player 接口。

## 职责
- PlayerImpl：播放队列、四种播放模式（sequential / listLoop / singleLoop / shuffle）、随机历史栈、状态流同步。
- 后台播放「侧车」：audio_service（Android 一期），见 src/audio_handler.dart；通知为渲染层，PlayMode 映射为 repeat / shuffle。
- Windows 平台通过 just_audio_windows 提供实现。

## 依赖
core、just_audio、audio_service、just_audio_windows。

## 测试
在 packages/player 下运行 flutter test。
