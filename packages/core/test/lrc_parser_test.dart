/// LrcParser 单元测试
///
/// 验证：
/// - 时间戳解析 [mm:ss.xx]
/// - 一行多个时间戳
/// - 元数据标签提取 (ti/ar)
/// - offset 偏移
/// - 按时间排序
/// - 空/非法输入容错

import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('LrcParser.parse', () {
    test('解析基本时间戳行', () {
      const lrc = '''
[ti:晴天]
[ar:周杰伦]
[00:12.00]故事的小黄花
[00:16.00]从出生那年就飘着
''';
      final lines = LrcParser.parse(lrc);

      expect(lines.length, 2);
      expect(lines[0].text, '故事的小黄花');
      expect(lines[0].time, const Duration(seconds: 12));
      expect(lines[1].text, '从出生那年就飘着');
      expect(lines[1].time, const Duration(seconds: 16));
    });

    test('解析毫秒部分（2 位）', () {
      const lrc = '[00:12.34]测试';
      final lines = LrcParser.parse(lrc);
      expect(lines.length, 1);
      expect(lines[0].time, const Duration(milliseconds: 12340));
    });

    test('解析毫秒部分（1 位）', () {
      const lrc = '[00:12.3]测试';
      final lines = LrcParser.parse(lrc);
      expect(lines.length, 1);
      expect(lines[0].time, const Duration(milliseconds: 12300));
    });

    test('一行多个时间戳生成多行', () {
      const lrc = '[00:12.00][00:20.00]同一句';
      final lines = LrcParser.parse(lrc);

      expect(lines.length, 2);
      expect(lines[0].text, '同一句');
      expect(lines[0].time, const Duration(seconds: 12));
      expect(lines[1].text, '同一句');
      expect(lines[1].time, const Duration(seconds: 20));
    });

    test('按时间排序', () {
      const lrc = '''
[00:30.00]最后
[00:10.00]最先
[00:20.00]中间
''';
      final lines = LrcParser.parse(lrc);
      expect(lines.map((l) => l.time).toList(), [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
        const Duration(seconds: 30),
      ]);
      expect(lines.map((l) => l.text).toList(), ['最先', '中间', '最后']);
    });

    test('忽略元数据行和空行', () {
      const lrc = '''
[ti:歌名]
[ar:歌手]
[al:专辑]
[00:12.00]唯一歌词

''';
      final lines = LrcParser.parse(lrc);
      expect(lines.length, 1);
      expect(lines.first.text, '唯一歌词');
    });

    test('空内容返回空列表', () {
      expect(LrcParser.parse(''), isEmpty);
      expect(LrcParser.parse('[ti:only metadata]'), isEmpty);
    });

    test('无时间戳的文本行被忽略', () {
      const lrc = '这是一行没有时间戳的文字\n[00:12.00]有歌词';
      final lines = LrcParser.parse(lrc);
      expect(lines.length, 1);
      expect(lines.first.text, '有歌词');
    });

    test('offset 正值让歌词提前', () {
      const lrc = '''
[offset:500]
[00:12.00]歌词
''';
      final lines = LrcParser.parse(lrc);
      // 12 秒 - 500ms = 11.5 秒
      expect(lines.first.time, const Duration(milliseconds: 11500));
    });

    test('offset 负值让歌词延后', () {
      const lrc = '''
[offset:-300]
[00:12.00]歌词
''';
      final lines = LrcParser.parse(lrc);
      // 12 秒 + 300ms = 12.3 秒
      expect(lines.first.time, const Duration(milliseconds: 12300));
    });
  });

  group('LrcParser 元数据', () {
    test('parseTitle 提取 ti 标签', () {
      const lrc = '[ti:晴天]\n[ar:周杰伦]';
      expect(LrcParser.parseTitle(lrc), '晴天');
    });

    test('parseArtist 提取 ar 标签', () {
      const lrc = '[ti:晴天]\n[ar:周杰伦]';
      expect(LrcParser.parseArtist(lrc), '周杰伦');
    });

    test('无标签返回 null', () {
      expect(LrcParser.parseTitle('[00:12.00]歌词'), isNull);
      expect(LrcParser.parseArtist('[00:12.00]歌词'), isNull);
    });
  });
}
