/// 歌词合并工具：把译文（tlyric 一类）按**时间戳对齐**并入原文 LRC
///
/// 为什么不能直接拼接两段 LRC：播放器按时间戳高亮，两段拼在一起只会变成
/// 「前面一整块原文 + 后面一整块译文」——用户看到的是失同步的双份歌词。
/// 因此这里以**原文时间轴**为准，把同一时间戳的译文并进同一行。
library;

/// LRC 时间戳：`[mm:ss]`、`[mm:ss.xx]`、`[mm:ss:xx]` 三种写法都收
final RegExp _kTimestamp = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

/// 合并结果
class LyricMergeResult {
  /// 合并后的歌词文本
  final String text;

  /// 原文里有效歌词行数（不含仅时间轴的空行）
  final int originalLines;

  /// 命中译文并合并的行数
  final int mergedLines;

  const LyricMergeResult({
    required this.text,
    required this.originalLines,
    required this.mergedLines,
  });
}

/// 把译文按时间戳合并进原文
///
/// 规则：
/// * [translation] 为空/全空白 → 原样返回原文（不算合并）；
/// * 同一时间戳：输出 `原文{join}译文`；
/// * 译文里时间戳对不上的行**忽略**（以原文时间轴为准，不凭空拉长时间轴）；
/// * 原文为纯文本（没有时间戳）或译文没有时间戳 → 原文末尾换行追加译文，
///   至少不丢译文。
LyricMergeResult mergeLyricTranslation(
  String original,
  String? translation, {
  String join = ' / ',
}) {
  final transText = translation?.trim() ?? '';
  final originalLines = _countLyricLines(original);
  if (transText.isEmpty) {
    return LyricMergeResult(
      text: original,
      originalLines: originalLines,
      mergedLines: 0,
    );
  }

  final byStamp = _indexByStamp(transText);
  // 原文没有时间轴，或译文根本没有时间戳：无法逐行对齐，退化为追加
  if (!_hasTimestamp(original) || byStamp.isEmpty) {
    return LyricMergeResult(
      text: '$original\n$transText',
      originalLines: originalLines,
      mergedLines: 0,
    );
  }

  final buffer = StringBuffer();
  var merged = 0;
  final rawLines = original.split('\n');
  for (var i = 0; i < rawLines.length; i++) {
    final raw = rawLines[i];
    if (i > 0) buffer.write('\n');
    final matches = _kTimestamp.allMatches(raw).toList();
    if (matches.isEmpty) {
      buffer.write(raw); // 头部元信息（[ti:]/[ar:]…）原样保留
      continue;
    }
    final text = raw.replaceAll(_kTimestamp, '').trim();
    if (text.isEmpty) {
      buffer.write(raw); // 纯时间轴的空行
      continue;
    }
    // 一行可挂多个时间戳（[00:01.00][00:05.00]词），任一命中即合并
    String? translated;
    for (final match in matches) {
      translated = byStamp[_stampMs(match)];
      if (translated != null) break;
    }
    if (translated == null) {
      buffer.write(raw);
      continue;
    }
    final prefix = matches.map((m) => m.group(0)!).join();
    buffer.write('$prefix$text$join$translated');
    merged++;
  }

  return LyricMergeResult(
    text: buffer.toString(),
    originalLines: originalLines,
    mergedLines: merged,
  );
}

/// 时间戳 → 译文文本
Map<int, String> _indexByStamp(String lrc) {
  final map = <int, String>{};
  for (final raw in lrc.split('\n')) {
    final matches = _kTimestamp.allMatches(raw).toList();
    if (matches.isEmpty) continue;
    final text = raw.replaceAll(_kTimestamp, '').trim();
    if (text.isEmpty) continue;
    for (final match in matches) {
      map[_stampMs(match)] = text;
    }
  }
  return map;
}

/// 时间戳 → 毫秒
int _stampMs(RegExpMatch match) {
  final minutes = int.parse(match.group(1)!);
  final seconds = int.parse(match.group(2)!);
  final fraction = match.group(3);
  var millis = 0;
  if (fraction != null && fraction.isNotEmpty) {
    // 两位是厘秒、三位是毫秒，都按"左对齐补零"换算
    millis = int.parse(fraction.padRight(3, '0').substring(0, 3));
  }
  return (minutes * 60 + seconds) * 1000 + millis;
}

/// 文本里是否出现时间戳
bool _hasTimestamp(String text) => _kTimestamp.hasMatch(text);

/// 有效歌词行数（带时间戳且文本非空）
int _countLyricLines(String lrc) {
  var count = 0;
  for (final raw in lrc.split('\n')) {
    if (!_kTimestamp.hasMatch(raw)) continue;
    if (raw.replaceAll(_kTimestamp, '').trim().isEmpty) continue;
    count++;
  }
  return count;
}
