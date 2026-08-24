/// 歌曲播放模式
enum PlayMode {
  /// 列表循环：播完最后一首后跳回第一首
  listLoop,

  /// 单曲循环：当前歌曲播放结束后自动重放
  singleLoop,

  /// 随机播放：在队列中随机选择下一首
  shuffle,

  /// 顺序播放：播完最后一首后停止
  sequential,
}