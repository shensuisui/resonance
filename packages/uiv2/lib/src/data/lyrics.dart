/// 歌词装配 —— 只消费音乐源返回的真实 [Lyrics]。
///
/// 演示歌词已经迁到 demo_source，由规则源通过 /lyrics/{id} 返回 LRC；
/// App 内不再保存任何歌词正文，也不再有“演示文本兜底”分支。
library;

import 'package:core/core.dart';

/// 歌词来源
enum LyricSource {
  /// 音乐源返回的 LRC / 已解析歌词
  lrc,

  /// 没有歌词
  none,
}

/// 一行歌词（[at] 为 null 表示段落间隔）
class LyricEntry {
  /// 行文本（空串 = 段落间隔）
  final String text;

  /// 该行起始时间（null = 不参与高亮）
  final Duration? at;

  /// 构造歌词行
  const LyricEntry({required this.text, this.at});

  /// 是否为段落间隔
  bool get isGap => text.isEmpty;
}

/// 装配结果：来源 + 行列表
class LyricScript {
  /// 来源
  final LyricSource source;

  /// 行列表
  final List<LyricEntry> entries;

  /// 构造装配结果
  const LyricScript({required this.source, required this.entries});

  /// 是否有可展示的歌词
  bool get hasLyrics => source != LyricSource.none && entries.isNotEmpty;
}

/// 把音乐源返回的 [Lyrics] 装配成 UI 脚本；空行保留为段落间隔。
LyricScript buildLyricScript({Lyrics? fromSource}) {
  final lines = fromSource?.lines ?? const <LyricLine>[];
  if (lines.isEmpty) {
    return const LyricScript(source: LyricSource.none, entries: []);
  }
  return LyricScript(
    source: LyricSource.lrc,
    entries: [
      for (final line in lines)
        LyricEntry(
          text: line.text,
          at: line.text.isEmpty ? null : line.time,
        ),
    ],
  );
}

/// 当前活动行下标（线性扫描：取最后一个 at <= pos）
int activeLyricIndex(List<LyricEntry> entries, Duration position) {
  var active = -1;
  for (var i = 0; i < entries.length; i++) {
    final at = entries[i].at;
    if (at != null && position >= at) active = i;
  }
  return active;
}
