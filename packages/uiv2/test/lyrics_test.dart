/// 歌词装配单元测试（lib/src/data/lyrics.dart）。
///
/// App 已不内置演示歌词；这里验证唯一真实来源路径与活动行扫描。
library;

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/data/lyrics.dart';

void main() {
  group('buildLyricScript', () {
    test('源歌词原样保留时间轴，空行是间隔', () {
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
      final script = buildLyricScript(fromSource: lrc);
      expect(script.source, LyricSource.lrc);
      expect(script.hasLyrics, isTrue);
      expect(script.entries, hasLength(3));
      expect(script.entries[1].isGap, isTrue);
      expect(script.entries[1].at, isNull);
      expect(script.entries[2].at, const Duration(seconds: 3));
    });
    test('无源歌词 -> none', () {
      final script = buildLyricScript(fromSource: null);
      expect(script.source, LyricSource.none);
      expect(script.hasLyrics, isFalse);
    });
    test('空行列表 -> none，不再有演示兜底', () {
      final script = buildLyricScript(
        fromSource: Lyrics(songId: 'x', sourceId: 'demo_catalog', lines: const []),
      );
      expect(script.source, LyricSource.none);
      expect(script.entries, isEmpty);
    });
  });
  group('activeLyricIndex 线性扫描', () {
    LyricEntry at(int s) => LyricEntry(text: 'x', at: Duration(seconds: s));
    test('未到首行 -> -1', () {
      expect(activeLyricIndex([at(10), at(20)], const Duration(seconds: 9)), -1);
    });
    test('取最后一个 at <= pos', () {
      final entries = [at(5), at(10), at(20)];
      expect(activeLyricIndex(entries, const Duration(seconds: 10)), 1);
      expect(activeLyricIndex(entries, const Duration(seconds: 25)), 2);
    });
    test('边界与空行', () {
      final entries = [at(5), const LyricEntry(text: ''), at(10)];
      expect(activeLyricIndex(entries, const Duration(seconds: 5)), 0);
      expect(activeLyricIndex(entries, const Duration(seconds: 10)), 2);
      expect(activeLyricIndex(const [], const Duration(seconds: 100)), -1);
    });
  });
}
