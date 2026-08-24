# Step 5: 播放器实现 (just_audio)

| 步骤 | 5 |
| :--- | :--- |
| 包 | `player` |
| 依赖 | Step 4（Player 接口） |
| 状态 | 待实现 |

---

## 1. 概述

`player` 包使用 `just_audio` 实现 `core` 包中定义的 `Player` 抽象接口。作为播放器实现层，可替换性通过接口保证。

## 2. 实现设计

### 2.1 PlayerImpl

```dart
class PlayerImpl implements Player {
  final AudioPlayer _audioPlayer = AudioPlayer();

  // 内部状态
  List<Song> _queue = [];
  int _currentIndex = -1;
  PlayMode _playMode = PlayMode.listLoop;
  List<int> _shuffleHistory = []; // 随机播放历史栈

  // Stream 控制器
  final _stateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<int>.broadcast();
  final _durationController = StreamController<int>.broadcast();
}
```

### 2.2 关键实现细节

- **播放模式**：通过 `_audioPlayer.loopMode` 和自定义逻辑组合实现
  - 列表循环：`LoopMode.all`
  - 单曲循环：`LoopMode.one`
  - 随机播放：手动管理 `_shuffleHistory` 栈
  - 顺序播放：`LoopMode.off`，播完停止
- **状态同步**：监听 `AudioPlayer.playerStateStream` 转换为 `PlayerState`
- **进度同步**：监听 `AudioPlayer.positionStream` 和 `durationStream`
- **上一首**：随机模式下从 `_shuffleHistory` 弹出，其他模式使用 `_currentIndex - 1`

## 3. 包结构变更

```
packages/player/lib/
├── player.dart
└── src/
    └── player_impl.dart
```

## 4. 依赖

pubspec.yaml 添加 `just_audio: ^0.9.43`

## 5. 测试用例

- Mock AudioPlayer 验证各方法调用
- 播放模式切换逻辑
- 队列管理（setQueue、jumpToIndex）
- 上一首/下一首在随机模式下的行为
- 状态转换正确性