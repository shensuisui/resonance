/// 歌词装配单元测试（lib/src/data/lyrics.dart）。
///
/// 测什么：
///   * [buildLyricScript] 三态：.lrc 优先 / 演示兜底 / 无歌词；
///   * 演示歌词时间轴算法：lead=5、span=max(24, duration-lead-6)、
///     非空行均分、空行是间隔不计时（at=null）；
///   * [activeLyricIndex] 线性扫描语义：取最后一个 at <= pos，未命中返回 -1。
///
/// 模拟数据来源：包内配表 kDemoLyrics 与手工构造的 core Lyrics/LyricLine。
library;

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/data/lyrics.dart';

void main() {
  group('buildLyricScript 三态', () {
    test('有 .lrc 时优先使用，不做演示时间轴改写', () {
      final lrc = Lyrics(
        songId: 'midnights#3',
        sourceId: 'demo_catalog',
        isLrc: true,
        lines: const [
          LyricLine(time: Duration(seconds: 1), text: '第一行'),
          LyricLine(time: Duration(seconds: 2), text: ''),
          LyricLine(time: Duration(seconds: 3), text: '第二行'),
        ],
      );
      final script = buildLyricScript(
        trackId: 'midnights#3',
        durationSeconds: 200,
        fromSource: lrc,
      );
      expect(script.source, LyricSource.lrc);
      expect(script.hasLyrics, isTrue);
      expect(script.entries.length, 3);
      // lrc 行的时间原样保留（空行 at=null 是间隔）
      expect(script.entries[0].at, const Duration(seconds: 1));
      expect(script.entries[0].text, '第一行');
      expect(script.entries[1].isGap, isTrue);
      expect(script.entries[1].at, isNull);
      expect(script.entries[2].at, const Duration(seconds: 3));
    });

    test('没有 .lrc 但配表有演示文本时兜底', () {
      final script = buildLyricScript(
        trackId: 'midnights#3',
        durationSeconds: 219,
      );
      expect(script.source, LyricSource.demo);
      expect(script.hasLyrics, isTrue);
      expect(script.entries.map((e) => e.text).toList(),
          kDemoLyrics['midnights#3']);
    });

    test('两者都没有 -> none 空脚本', () {
      final script = buildLyricScript(
        trackId: '不存在的曲目',
        durationSeconds: 200,
      );
      expect(script.source, LyricSource.none);
      expect(script.entries, isEmpty);
      expect(script.hasLyrics, isFalse);
    });

    test('fromSource 的空行列表不拦截演示兜底', () {
      // lines 为空表示 .lrc 解析失败，应走演示兜底
      final empty = Lyrics(
        songId: 'midnights#3',
        sourceId: 'demo_catalog',
        lines: const [],
      );
      final script = buildLyricScript(
        trackId: 'midnights#3',
        durationSeconds: 219,
        fromSource: empty,
      );
      expect(script.source, LyricSource.demo);
    });
  });

  group('演示歌词时间轴算法', () {
    test('首行时间 = lead（5 秒）', () {
      final script = buildLyricScript(
        trackId: 'midnights#3',
        durationSeconds: 219,
      );
      final first = script.entries.firstWhere((e) => !e.isGap);
      expect(first.at, const Duration(seconds: 5));
    });

    test('span = max(24, duration - lead - 6)，非空行均分', () {
      // duration=200：span = 200-5-6 = 189，midnights#3 有 16 非空行
      const duration = 200;
      final script = buildLyricScript(
        trackId: 'midnights#3',
        durationSeconds: duration,
      );
      final timed = kDemoLyrics['midnights#3']!
          .where((l) => l.isNotEmpty)
          .length;
      final span = duration - kLyricLead - 6;
      expect(span, 189);
      final step = span / timed;
      final expectedLast = kLyricLead + step * (timed - 1);
      final lastTimed =
          script.entries.lastWhere((e) => e.at != null);
      expect(lastTimed.at!.inMilliseconds, (expectedLast * 1000).round());
      // 相邻两个非空行的间隔恒为 step
      final timedEntries = script.entries.where((e) => e.at != null).toList();
      for (var i = 1; i < timedEntries.length; i++) {
        final delta = timedEntries[i].at! - timedEntries[i - 1].at!;
        expect(delta.inMilliseconds, (step * 1000).round());
      }
    });

    test('时长很短时 span 下限为 24 秒', () {
      // duration=20：20-5-6=9 < 24，span 应取 24
      const duration = 20;
      final script = buildLyricScript(
        trackId: 'future-nostalgia#2',
        durationSeconds: duration,
      );
      final timed = kDemoLyrics['future-nostalgia#2']!
          .where((l) => l.isNotEmpty)
          .length;
      const span = 24.0;
      final step = span / timed;
      final timedEntries = script.entries.where((e) => e.at != null).toList();
      expect(timedEntries.length, timed);
      final lastAt = timedEntries.last.at!;
      expect(lastAt.inMilliseconds / 1000,
          closeTo(kLyricLead + step * (timed - 1), 0.01));
      // 首行仍是 lead
      expect(timedEntries.first.at, const Duration(seconds: 5));
    });

    test('空行是段落间隔：不计时间、at=null、isGap=true', () {
      final script = buildLyricScript(
        trackId: 'midnights#3',
        durationSeconds: 200,
      );
      final gaps = script.entries.where((e) => e.isGap).toList();
      // midnights#3 配表里有 2 个空行
      expect(gaps.length, 2);
      for (final gap in gaps) {
        expect(gap.at, isNull);
        expect(gap.text, isEmpty);
      }
      // 空行不占 step：非空行数与配表一致
      final timedCount = script.entries.where((e) => e.at != null).length;
      expect(timedCount,
          kDemoLyrics['midnights#3']!.where((l) => l.isNotEmpty).length);
    });
  });

  group('activeLyricIndex 线性扫描', () {
    LyricEntry at(int s) => LyricEntry(text: 'x', at: Duration(seconds: s));

    test('未到首行 -> -1', () {
      expect(
          activeLyricIndex([at(10), at(20)], const Duration(seconds: 9)), -1);
    });

    test('取最后一个 at <= pos（而不是第一个）', () {
      final entries = [at(5), at(10), at(20)];
      expect(activeLyricIndex(entries, const Duration(seconds: 10)), 1);
      expect(activeLyricIndex(entries, const Duration(seconds: 25)), 2);
    });

    test('边界：pos 恰好等于 at 时命中', () {
      final entries = [at(5), at(10)];
      expect(activeLyricIndex(entries, const Duration(seconds: 5)), 0);
      expect(activeLyricIndex(entries, const Duration(seconds: 10)), 1);
    });

    test('at=null 的间隔行不参与命中', () {
      final entries = [at(5), const LyricEntry(text: ''), at(10)];
      expect(activeLyricIndex(entries, const Duration(seconds: 10)), 2);
      expect(activeLyricIndex(entries, const Duration(seconds: 7)), 0);
    });

    test('空列表 -> -1', () {
      expect(activeLyricIndex(const [], const Duration(seconds: 100)), -1);
    });
  });

  group('kDemoLyrics 配表完整性', () {
    test('每个演示条目都有非空行，且键都是曲目 id 形式', () {
      expect(kDemoLyrics, isNotEmpty);
      for (final entry in kDemoLyrics.entries) {
        expect(entry.key.contains('#'), isTrue, reason: entry.key);
        expect(entry.value.any((l) => l.isNotEmpty), isTrue,
            reason: entry.key);
      }
    });
  });
}
