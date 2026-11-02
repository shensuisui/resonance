/// 播放进度（按队列记录）
///
/// 为什么要"按队列"记：用户要求关闭 App 后能从上次的**队列 + 曲目 + 进度**
/// 继续；同时歌单详情要有「继续播放」——那就必须知道**每个歌单各自**听到哪了，
/// 只记一条"全局最后播放"满足不了。
///
/// 只存三样东西：队列身份（种类 + id）、曲目全局键、毫秒进度。
/// 队列的曲目列表**不存**：歌单/最近播放/我喜欢/本地音乐都能从数据库推导，
/// 存了反而会与真实数据不一致（歌单删了歌，队列里还留着）。
library;

/// 一个队列的播放进度
class PlayProgress {
  /// 队列种类（recent / playlist / liked / local，与 UI 层 PlayQueueKind 同名）
  final String queueKind;

  /// 队列 id：歌单队形为歌单 id，其它种类为空串
  final String queueId;

  /// 曲目全局键（Song.globalKey）
  final String songKey;

  /// 毫秒进度
  final int positionMs;

  /// 最后更新时间（毫秒时间戳，用于清理与调试）
  final int updatedAt;

  /// 构造
  const PlayProgress({
    required this.queueKind,
    required this.songKey,
    required this.positionMs,
    required this.updatedAt,
    this.queueId = '',
  });

  /// 身份键（日志与断言用）
  String get identity => queueId.isEmpty ? queueKind : queueKind + ':' + queueId;

  @override
  String toString() => 'PlayProgress(' + identity + ', ' + songKey + ', ' +
      positionMs.toString() + 'ms)';
}

/// 播放进度 DAO 接口
abstract class PlayProgressDao {
  /// 取某个队列的进度（没有则 null）
  Future<PlayProgress?> get(String queueKind, String queueId);

  /// 写入/覆盖某个队列的进度（同一队列只保留最新一条）
  Future<void> upsert(PlayProgress progress);

  /// 删除某个队列的进度（歌单被删时调用）
  Future<void> delete(String queueKind, String queueId);

  /// 全部进度（启动时算"上次活跃队列"等场景）
  Future<List<PlayProgress>> getAll();
}
