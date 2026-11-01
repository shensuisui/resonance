import 'dart:async';

import 'package:core/core.dart';

/// 播放器抽象接口，纯 Dart 定义，不依赖 Flutter
abstract class Player {
  /// 当前播放器状态流
  Stream<PlayerState> get stateStream;

  /// 当前播放器状态（快照）
  PlayerState get currentState;

  /// 当前播放进度流（毫秒）
  Stream<int> get positionStream;

  /// 当前播放进度（毫秒，快照）
  int get currentPosition;

  /// 当前歌曲总时长流（毫秒）
  Stream<int> get durationStream;

  /// 当前歌曲总时长（毫秒，快照）
  int get currentDuration;

  /// 当前播放模式
  PlayMode get playMode;

  /// 设置播放模式
  set playMode(PlayMode mode);

  /// 加载并播放歌曲
  Future<void> play(Song song);

  /// 暂停
  Future<void> pause();

  /// 恢复播放
  Future<void> resume();

  /// 停止
  Future<void> stop();

  /// 跳转到指定位置（毫秒）
  Future<void> seek(Duration position);

  /// 设置音量（0.0 ~ 1.0）
  Future<void> setVolume(double volume);

  /// 获取当前音量
  double get volume;

  /// 播放下一首（根据 PlayMode 决定）
  Future<void> next();

  /// 播放上一首（根据 PlayMode 和播放历史决定）
  Future<void> previous();

  /// 设置播放队列
  void setQueue(List<Song> songs);

  /// 获取当前播放队列
  List<Song> get queue;

  /// 获取当前播放索引
  int get currentIndex;

  /// 跳转到队列中指定索引
  Future<void> jumpToIndex(int index);

  /// 释放播放器资源
  Future<void> dispose();
}

/// 「能广播当前曲目」的播放器契约
///
/// 为什么不做成 [Player] 的成员：Dart 里 implements 不继承具体实现，
/// 加进接口会让所有测试桩/预览实现都必须补实现。这里用独立契约，
/// 谁需要就实现它，UI 侧用 `is` 判断 —— 零破坏、可渐进接入。
abstract class CurrentSongSource {
  /// 当前曲目变化流：索引一变就广播（点播 / 上一首 / 下一首 / 自动续播）
  Stream<Song?> get currentSongStream;
}

/// [Player] 的便捷派生：当前曲目 = 队列里索引指向的那一首
extension PlayerCurrentSong on Player {
  /// 当前曲目（永不与播放器内部状态脱节）
  Song? get currentSong {
    final index = currentIndex;
    return (index >= 0 && index < queue.length) ? queue[index] : null;
  }
}