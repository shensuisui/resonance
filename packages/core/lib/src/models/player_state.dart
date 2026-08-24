/// 播放器状态
enum PlayerState {
  /// 空闲
  idle,

  /// 加载中
  loading,

  /// 播放中
  playing,

  /// 已暂停
  paused,

  /// 已停止
  stopped,

  /// 播放出错
  error,
}