/// LRC 歌词解析器
///
/// 解析标准 LRC 格式：
/// - 元数据标签 [ti:], [ar:], [al:], [offset:]
/// - 时间戳行 [mm:ss.xx]文本
/// - 一行多个时间戳 [00:12.00][00:20.00]文本（为每个时间戳生成一行）
///
/// offset 约定：正值表示歌词整体提前（时间戳减去 offset 毫秒）。

import '../models/lyrics.dart';

class LrcParser {
  LrcParser._();

  /// 歌词 → LRC 文本（与 [parse] 成对）
  ///
  /// 源层只返回解析后的 [Lyrics]，而缓存要写进 songs 表的 TEXT 列，
  /// 所以需要转回文本。带时间轴时按 [mm:ss.xx] 逐行输出；
  /// 无时间轴（纯文本歌词）时按行输出，读取端会还原成单行文本。
  static String toLrc(Lyrics lyrics) {
    final buf = StringBuffer();
    for (final line in lyrics.lines) {
      if (!lyrics.isLrc) {
        buf.writeln(line.text);
        continue;
      }
      final ms = line.time.inMilliseconds;
      final mm = (ms ~/ 60000).toString().padLeft(2, '0');
      final ss = ((ms % 60000) ~/ 1000).toString().padLeft(2, '0');
      final cs = ((ms % 1000) ~/ 10).toString().padLeft(2, '0');
      buf.writeln('[$mm:$ss.$cs]${line.text}');
    }
    return buf.toString().trimRight();
  }

  /// 解析 LRC 文本为歌词行列表（按时间排序）
  ///
  /// 无时间戳的行（元数据标签等）被忽略。
  static List<LyricLine> parse(String lrcText) {
    final lines = <LyricLine>[];
    final offset = _parseOffset(lrcText);

    final timeRegex = RegExp(r'\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
    for (final raw in lrcText.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      final timeMatches = timeRegex.allMatches(line).toList();
      if (timeMatches.isEmpty) continue; // 元数据行或无时间戳行

      // 提取文本（移除所有时间戳标签）
      var text = line;
      for (final m in timeMatches) {
        text = text.replaceFirst(m.group(0)!, '');
      }
      text = text.trim();

      for (final m in timeMatches) {
        final minutes = int.parse(m.group(1)!);
        final seconds = int.parse(m.group(2)!);
        var ms = minutes * 60000 + seconds * 1000;

        // 毫秒部分（1~3 位小数）
        final frac = m.group(3);
        if (frac != null) {
          if (frac.length == 1) {
            ms += int.parse(frac) * 100;
          } else if (frac.length == 2) {
            ms += int.parse(frac) * 10;
          } else {
            ms += int.parse(frac);
          }
        }

        ms -= offset;
        lines.add(LyricLine(time: Duration(milliseconds: ms), text: text));
      }
    }

    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  /// 解析 [offset:±ms] 标签，未提供返回 0
  static int _parseOffset(String lrcText) {
    final m = RegExp(r'\[offset:([+-]?\d+)\]').firstMatch(lrcText);
    if (m == null) return 0;
    return int.parse(m.group(1)!);
  }

  /// 提取歌曲标题（[ti:] 标签）
  static String? parseTitle(String lrcText) {
    final m = RegExp(r'\[ti:(.*?)\]').firstMatch(lrcText);
    return m?.group(1)?.trim();
  }

  /// 提取歌手（[ar:] 标签）
  static String? parseArtist(String lrcText) {
    final m = RegExp(r'\[ar:(.*?)\]').firstMatch(lrcText);
    return m?.group(1)?.trim();
  }
}
