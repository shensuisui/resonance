import 'dart:math';

/// 随机播放的「一轮不重复」抽签袋。
///
/// 为什么单独抽出来：抽签规则是纯逻辑，也是随机播放唯一的易错点 ——
/// 旧实现直接用 `DateTime.now().microsecondsSinceEpoch % 队列长度` 当随机下标，
/// 既不均匀、又没有任何「一轮内不重复」的保证，可能连着抽到刚播过的歌。
/// 抽成纯逻辑后可以脱离 AudioPlayer 单测：[PlayerImpl] 内部直接 new AudioPlayer()，
/// 没有注入口，在测试里根本构造不出来。
class ShuffleBag {
  /// 本轮还没抽过、且不是当前曲目的下标
  final List<int> _pool = [];

  /// 随机源；测试可注入定种子的 [Random] 让结果可复现
  final Random _rng;

  /// 构造抽签袋
  ShuffleBag({Random? rng}) : _rng = rng ?? Random();

  /// 本轮还剩几个待抽
  int get remaining => _pool.length;

  /// 开始新一轮：把 `0..length-1` 装进袋里，并排除 [exclude]（通常是当前曲目，避免立刻重复）
  ///
  /// 换队列、切到随机模式、或一轮抽完时都要调用。
  void reset(int length, {required int exclude}) {
    _pool
      ..clear()
      ..addAll(List<int>.generate(length, (i) => i).where((i) => i != exclude));
  }

  /// 抽一个下标（抽过就从袋里移除，因此一轮内不会重复）；袋空返回 null
  ///
  /// 返回 null 有两种含义：整轮已抽完（调用方 reset 后继续），
  /// 或袋里本来就没有可抽项（例如队列只有一首歌，调用方兜底）。
  int? take() =>
      _pool.isEmpty ? null : _pool.removeAt(_rng.nextInt(_pool.length));
}
