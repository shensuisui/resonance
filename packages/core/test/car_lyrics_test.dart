/// 车载歌词映射与行选择单测
///
/// 覆盖：显示范围矩阵（off/car/all × 蓝牙 × 车机）、槽位映射（title/artist）、
/// 歌曲信息格式、歌词行二分查找（含空行/边界）。

import 'package:core/core.dart';
import 'package:test/test.dart';

/// 构造一个歌词行
LyricLine line(int ms, String text) =>
    LyricLine(time: Duration(milliseconds: ms), text: text);

void main() {
  group('formatSongInfo', () {
    test('歌手 - 歌名', () {
      expect(formatSongInfo(title: '夜行', artist: '陈粒'), '陈粒 - 夜行');
    });
    test('缺歌手只留歌名', () {
      expect(formatSongInfo(title: '夜行', artist: '  '), '夜行');
    });
    test('缺歌名只留歌手', () {
      expect(formatSongInfo(title: '', artist: '陈粒'), '陈粒');
    });
    test('都空', () {
      expect(formatSongInfo(title: '', artist: ''), '');
    });
  });

  group('resolveCarLyricsMetadata 显示范围矩阵', () {
    const line = '把孤独写成诗';

    CarLyricsMetadata? resolve({
      required CarLyricsScope scope,
      required bool bt,
      required bool car,
      CarLyricsSlot slot = CarLyricsSlot.title,
    }) =>
        resolveCarLyricsMetadata(
          config: CarLyricsConfig(scope: scope, slot: slot),
          bluetoothConnected: bt,
          carDetected: car,
          lyricLine: line,
          songTitle: '夜行',
          songArtist: '陈粒',
        );

    test('off：任何情况都不注入', () {
      expect(resolve(scope: CarLyricsScope.off, bt: true, car: true), isNull);
    });

    test('car + 车载 + 已连蓝牙：注入', () {
      expect(
        resolve(scope: CarLyricsScope.car, bt: true, car: true),
        const CarLyricsMetadata(title: '把孤独写成诗', artist: '陈粒 - 夜行'),
      );
    });

    test('car + 非车载：不注入', () {
      expect(resolve(scope: CarLyricsScope.car, bt: true, car: false), isNull);
    });

    test('all + 非车载：也注入', () {
      expect(
        resolve(scope: CarLyricsScope.all, bt: true, car: false),
        const CarLyricsMetadata(title: '把孤独写成诗', artist: '陈粒 - 夜行'),
      );
    });

    test('all + 未连蓝牙：不注入', () {
      expect(resolve(scope: CarLyricsScope.all, bt: false, car: false), isNull);
    });

    test('无歌词行：不注入', () {
      expect(
        resolveCarLyricsMetadata(
          config: const CarLyricsConfig(scope: CarLyricsScope.all),
          bluetoothConnected: true,
          carDetected: true,
          lyricLine: '   ',
          songTitle: '夜行',
          songArtist: '陈粒',
        ),
        isNull,
      );
    });
  });

  group('slot 映射', () {
    CarLyricsMetadata meta(CarLyricsSlot slot) => resolveCarLyricsMetadata(
          config: CarLyricsConfig(scope: CarLyricsScope.all, slot: slot),
          bluetoothConnected: true,
          carDetected: true,
          lyricLine: '把孤独写成诗',
          songTitle: '夜行',
          songArtist: '陈粒',
        )!;

    test('title 槽：第一行歌词，第二行歌手 - 歌名', () {
      expect(meta(CarLyricsSlot.title), const CarLyricsMetadata(title: '把孤独写成诗', artist: '陈粒 - 夜行'));
    });

    test('artist 槽：第一行歌手 - 歌名，第二行歌词', () {
      expect(meta(CarLyricsSlot.artist), const CarLyricsMetadata(title: '陈粒 - 夜行', artist: '把孤独写成诗'));
    });
  });

  group('carLyricLineIndexAt', () {
    final lines = <LyricLine>[
      line(0, ''),
      line(1000, '第一句'),
      line(3000, '第二句'),
      line(5000, ''),
      line(6000, '第三句'),
    ];

    test('播放前返回 null', () {
      expect(carLyricLineIndexAt(lines, Duration.zero), isNull);
    });

    test('命中第一句', () {
      expect(carLyricLineIndexAt(lines, const Duration(milliseconds: 1500)), 1);
    });

    test('空行回退到上一句非空', () {
      expect(carLyricLineIndexAt(lines, const Duration(milliseconds: 5500)), 2);
    });

    test('命中第三句', () {
      expect(carLyricLineIndexAt(lines, const Duration(milliseconds: 6500)), 4);
    });

    test('空列表返回 null', () {
      expect(carLyricLineIndexAt(const <LyricLine>[], const Duration(seconds: 1)), isNull);
    });

    test('只有空行返回 null', () {
      expect(carLyricLineIndexAt(<LyricLine>[line(0, ' ')], const Duration(seconds: 1)), isNull);
    });
  });
}
