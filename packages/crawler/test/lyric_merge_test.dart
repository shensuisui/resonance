// 歌词译文合并（纯函数）单元测试
//
// 背景：网易云等源同时返回 lyric（原文 LRC）与 tlyric（译文 LRC）。
// 两段直接拼接会得到"前一半原文 + 后一半译文"的失同步歌词，
// 所以引擎按时间戳把译文并进同一行。这里覆盖对齐、缺译、脏数据三类边界。

import 'package:crawler/crawler.dart';
import 'package:test/test.dart';

void main() {
  group('mergeLyricTranslation', () {
    test('同一时间戳合并为「原文 / 译文」，行数与原文一致', () {
      const original = '[00:01.00]Hello\n[00:05.00]World';
      const translation = '[00:01.00]你好\n[00:05.00]世界';

      final result = mergeLyricTranslation(original, translation);

      expect(result.text.split('\n'),
          ['[00:01.00]Hello / 你好', '[00:05.00]World / 世界']);
      expect(result.mergedLines, 2, reason: '两行都命中译文');
      expect(result.originalLines, 2);
    });

    test('译文为空/全空白 → 原样返回原文（不算合并）', () {
      const original = '[00:01.00]Hello';
      for (final empty in [null, '', '   ', '\n']) {
        final result = mergeLyricTranslation(original, empty);
        expect(result.text, original, reason: '译文「$empty」不该改变原文');
        expect(result.mergedLines, 0);
      }
    });

    test('译文里时间戳对不上的行被忽略（不拉长时间轴）', () {
      const original = '[00:01.00]Hello\n[00:05.00]World';
      const translation = '[00:01.00]你好\n[00:09.00]多余的译文';

      final result = mergeLyricTranslation(original, translation);

      expect(result.text.split('\n'),
          ['[00:01.00]Hello / 你好', '[00:05.00]World']);
      expect(result.mergedLines, 1);
      expect(result.text.contains('多余的译文'), isFalse);
    });

    test('自定义连接符生效', () {
      final result = mergeLyricTranslation(
          '[00:01.00]Hello', '[00:01.00]你好',
          join: ' · ');
      expect(result.text, '[00:01.00]Hello · 你好');
    });

    test('原文没有时间戳（纯文本歌词）→ 末尾追加译文', () {
      final result = mergeLyricTranslation('纯文本歌词', 'Pure lyrics');
      expect(result.text, '纯文本歌词\nPure lyrics');
      expect(result.originalLines, 0);
    });

    test('译文没有时间戳 → 末尾追加，不丢译文', () {
      final result = mergeLyricTranslation('[00:01.00]Hello', '你好');
      expect(result.text, '[00:01.00]Hello\n你好');
    });

    test('头部元信息与空时间轴行原样保留', () {
      const original = '[ti:歌名]\n[00:01.00]Hello\n[00:05.00]';
      const translation = '[00:01.00]你好';

      final result = mergeLyricTranslation(original, translation);

      expect(result.text.split('\n'),
          ['[ti:歌名]', '[00:01.00]Hello / 你好', '[00:05.00]']);
      expect(result.originalLines, 1, reason: '只有一行有效歌词');
    });

    test('一行挂多个时间戳：任一时间戳命中即合并', () {
      const original = '[00:01.00][00:05.00]副歌';
      const translation = '[00:05.00]Chorus';

      final result = mergeLyricTranslation(original, translation);

      expect(result.text, '[00:01.00][00:05.00]副歌 / Chorus');
      expect(result.mergedLines, 1);
    });

    test('两位小数按厘秒换算（[00:01.50] 对齐 [00:01.500]）', () {
      final result =
          mergeLyricTranslation('[00:01.50]Hello', '[00:01.500]你好');
      expect(result.text, '[00:01.50]Hello / 你好');
      expect(result.mergedLines, 1);
    });
  });
}
