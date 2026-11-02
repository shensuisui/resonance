/// 「播放地址 + 同一次请求顺带取回的元数据」
///
/// 背景：规则源的详情接口一次就同时给出播放地址和封面/歌手/时长，
/// 但 [MusicSource.getSongUrl] 只回传地址、把元数据丢掉了。后果有两个：
///   * 只解析地址的路径（下一首 / 上一首 / 跳转）永远拿不到封面 ——
///     没人去取过它的元数据，所以封面连"迟到"的机会都没有；
///   * 首播要么先空着封面，要么为了封面再请求一次同一个详情接口。
/// 因此把"地址 + 元数据"一起返回，让一次请求的信息量不再被丢弃。
library;

import 'playback_challenge.dart';
import 'song.dart';

/// 播放地址与顺带取回的元数据
class PlayableInfo {
  /// 播放地址（源没给时为空串）
  final String url;

  /// 同一次请求里顺带取到的曲目元数据（源不提供时为 null）
  final Song? meta;

  /// 源站要求人机验证时带回的挑战（含验证图）；不需要验证时为 null
  final PlaybackChallenge? challenge;

  /// 构造
  const PlayableInfo({required this.url, this.meta, this.challenge});

  /// 是否拿到了可用的播放地址
  bool get hasUrl => url.isNotEmpty;

  /// 是否卡在源站的人机验证上（此时 url 必然为空）
  bool get needsChallenge => challenge != null;

  @override
  String toString() =>
      'PlayableInfo(url: $url, meta: ${meta?.globalKey ?? 'null'})';
}
