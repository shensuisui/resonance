/// PlaylistCodec 单元测试
///
/// 验证 M3U / PLS / JSON 编解码：
/// - 编码输出格式正确
/// - 解码还原条目（含 "Artist - Title" 解析）
/// - 空输入/异常输入容错
/// - 往返一致性（encode → decode 还原）

import 'dart:convert';
import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  final songs = [
    const PlaylistEntry(
      title: '稻香', artist: '周杰伦',
      url: 'http://example.com/1.mp3',
    ),
    const PlaylistEntry(
      title: '晴天', artist: '周杰伦',
      localPath: '/music/晴天.mp3',
    ),
    const PlaylistEntry(title: '孤勇者', artist: '陈奕迅'),
  ];

  group('M3U', () {
    test('encodeM3U 生成标准格式', () {
      final m3u = PlaylistCodec.encodeM3U(songs);
      expect(m3u, startsWith('#EXTM3U\n'));
      expect(m3u, contains('#EXTINF:-1,周杰伦 - 稻香\nhttp://example.com/1.mp3'));
      expect(m3u, contains('#EXTINF:-1,周杰伦 - 晴天\n/music/晴天.mp3'));
    });

    test('decodeM3U 还原条目（含 Artist - Title 解析）', () {
      final m3u = PlaylistCodec.encodeM3U(songs);
      final decoded = PlaylistCodec.decodeM3U(m3u);

      // 孤勇者无来源，编码时被跳过，只有 2 条
      expect(decoded.length, 2);
      expect(decoded[0].title, '稻香');
      expect(decoded[0].artist, '周杰伦');
      expect(decoded[0].url, 'http://example.com/1.mp3');
      expect(decoded[1].localPath, '/music/晴天.mp3');
    });

    test('decodeM3U 处理无 #EXTINF 的裸来源行', () {
      final decoded = PlaylistCodec.decodeM3U('#EXTM3U\nhttp://example.com/a.mp3');
      expect(decoded.length, 1);
      expect(decoded.first.url, 'http://example.com/a.mp3');
    });

    test('decodeM3U 空内容返回空列表', () {
      expect(PlaylistCodec.decodeM3U(''), isEmpty);
      expect(PlaylistCodec.decodeM3U('#EXTM3U\n\n'), isEmpty);
    });

    test('decodeM3U 忽略注释行', () {
      final decoded = PlaylistCodec.decodeM3U(
          '#EXTM3U\n#COMMENT line\nhttp://example.com/b.mp3');
      expect(decoded.length, 1);
      expect(decoded.first.url, 'http://example.com/b.mp3');
    });
  });

  group('PLS', () {
    test('encodePLS 生成标准格式', () {
      final pls = PlaylistCodec.encodePLS(songs);
      expect(pls, startsWith('[playlist]\n'));
      // 孤勇者无来源被跳过，只有 2 条
      expect(pls, contains('NumberOfEntries=2'));
      expect(pls, contains('File1=http://example.com/1.mp3'));
      expect(pls, contains('Title2=周杰伦 - 晴天'));
      expect(pls, contains('Version=2'));
    });

    test('decodePLS 还原条目', () {
      final pls = PlaylistCodec.encodePLS(songs);
      final decoded = PlaylistCodec.decodePLS(pls);

      expect(decoded.length, 2);
      expect(decoded[0].title, '稻香');
      expect(decoded[0].artist, '周杰伦');
      expect(decoded[0].url, 'http://example.com/1.mp3');
      expect(decoded[1].localPath, '/music/晴天.mp3');
    });

    test('decodePLS 空内容返回空列表', () {
      expect(PlaylistCodec.decodePLS(''), isEmpty);
      expect(PlaylistCodec.decodePLS('[playlist]\nVersion=2'), isEmpty);
    });
  });

  group('JSON', () {
    test('encodeJson 生成含歌单名的 JSON', () {
      final json = PlaylistCodec.encodeJson('我的歌单', songs);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['name'], '我的歌单');
      expect((decoded['songs'] as List).length, 3);
    });

    test('decodeJson 还原歌单名和条目', () {
      final json = PlaylistCodec.encodeJson('我的歌单', songs);
      final result = PlaylistCodec.decodeJson(json);

      expect(result.name, '我的歌单');
      expect(result.entries.length, 3);
      expect(result.entries[0].title, '稻香');
      expect(result.entries[1].localPath, '/music/晴天.mp3');
    });

    test('decodeJson 非法 JSON 返回空', () {
      final result = PlaylistCodec.decodeJson('not json');
      expect(result.entries, isEmpty);
      expect(result.name, isNull);
    });
  });

  group('PlaylistEntry', () {
    test('source 优先本地路径', () {
      const entry = PlaylistEntry(
        title: 't', artist: 'a',
        url: 'http://x.com', localPath: '/local/x.mp3',
      );
      expect(entry.source, '/local/x.mp3');
    });

    test('displayTitle 为 Artist - Title', () {
      const entry = PlaylistEntry(title: '晴天', artist: '周杰伦');
      expect(entry.displayTitle, '周杰伦 - 晴天');
    });

    test('displayTitle 无歌手时只有标题', () {
      const entry = PlaylistEntry(title: '晴天', artist: '');
      expect(entry.displayTitle, '晴天');
    });
  });
}
