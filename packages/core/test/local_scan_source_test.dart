/// LocalScanSource 单元测试
///
/// 使用真实临时目录 + 音频文件，验证：
/// - scanDirectory 递归扫描
/// - 文件名解析 "Artist - Title" 格式
/// - 文件名解析退化（用父目录名做歌手）
/// - 增量更新（已扫描文件跳过）
/// - search 按关键词过滤
/// - clear 清除数据
/// - loadFromDatabase 从数据库恢复
/// - 非音频文件被跳过
/// - 不存在的目录抛异常

import 'dart:io';
import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  late InMemoryDatabaseProvider db;
  late LocalScanSource source;

  setUp(() {
    db = InMemoryDatabaseProvider();
    source = LocalScanSource(db.songDao);
  });

  group('LocalScanSource', () {
    test('扫描空目录返回 0', () async {
      final tempDir = await Directory.systemTemp.createTemp('resonance_empty_');
      await source.init();
      final count = await source.scanDirectory(tempDir.path);
      expect(count, 0);
      await tempDir.delete(recursive: true);
    });

    test('扫描非音频文件返回 0', () async {
      final tempDir = await Directory.systemTemp.createTemp('resonance_noaudio_');
      final file = File('${tempDir.path}/readme.txt');
      await file.writeAsString('not audio');
      await source.init();
      final count = await source.scanDirectory(tempDir.path);
      expect(count, 0);
      await tempDir.delete(recursive: true);
    });

    test('扫描单个 mp3 文件', () async {
      final tempDir = await Directory.systemTemp.createTemp('resonance_one_');
      final file = File('${tempDir.path}/周杰伦 - 稻香.mp3');
      await file.writeAsBytes([0x00]); // 空内容即可，只测元数据解析

      await source.init();
      final count = await source.scanDirectory(tempDir.path);

      expect(count, 1);
      final songs = source.getScannedSongs();
      expect(songs.length, 1);
      expect(songs.first.title, '稻香');
      expect(songs.first.artist, '周杰伦');
      expect(songs.first.sourceId, 'local_scan');
      expect(songs.first.localPath, endsWith('周杰伦 - 稻香.mp3'));

      await tempDir.delete(recursive: true);
    });

    test('文件名无分隔符时用父目录名做歌手', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('resonance_nodash_');
      // 创建子目录
      final subDir = Directory('${tempDir.path}/周杰伦');
      await subDir.create();
      final file = File('${subDir.path}/晴天.mp3');
      await file.writeAsBytes([0x00]);

      await source.init();
      final count = await source.scanDirectory(tempDir.path);

      expect(count, 1);
      final songs = source.getScannedSongs();
      expect(songs.first.title, '晴天');
      expect(songs.first.artist, '周杰伦');

      await tempDir.delete(recursive: true);
    });

    test('递归扫描子目录', () async {
      final tempDir = await Directory.systemTemp.createTemp('resonance_recur_');
      // 子目录 1
      final sub1 = Directory('${tempDir.path}/album1');
      await sub1.create();
      await File('${sub1.path}/track1.mp3').writeAsBytes([0x00]);
      // 子目录 2
      final sub2 = Directory('${tempDir.path}/album2');
      await sub2.create();
      await File('${sub2.path}/track2.flac').writeAsBytes([0x00]);

      await source.init();
      final count = await source.scanDirectory(tempDir.path);

      expect(count, 2);
      await tempDir.delete(recursive: true);
    });

    test('增量更新：已扫描文件跳过', () async {
      final tempDir = await Directory.systemTemp.createTemp('resonance_incr_');
      await File('${tempDir.path}/song1.mp3').writeAsBytes([0x00]);
      await File('${tempDir.path}/song2.mp3').writeAsBytes([0x00]);

      await source.init();
      // 第一次扫描
      final count1 = await source.scanDirectory(tempDir.path);
      expect(count1, 2);

      // 第二次扫描，已有文件跳过
      final count2 = await source.scanDirectory(tempDir.path);
      expect(count2, 0);

      // 新增文件
      await File('${tempDir.path}/song3.mp3').writeAsBytes([0x00]);
      final count3 = await source.scanDirectory(tempDir.path);
      expect(count3, 1);

      await tempDir.delete(recursive: true);
    });

    test('search 按标题关键词过滤', () async {
      final tempDir = await Directory.systemTemp.createTemp('resonance_search_');
      await File('${tempDir.path}/周杰伦 - 稻香.mp3').writeAsBytes([0x00]);
      await File('${tempDir.path}/周杰伦 - 晴天.mp3').writeAsBytes([0x00]);
      await File('${tempDir.path}/陈奕迅 - 孤勇者.mp3').writeAsBytes([0x00]);

      await source.init();
      await source.scanDirectory(tempDir.path);

      // 按标题搜索
      final byTitle = await source.search(keyword: '稻香');
      expect(byTitle.songs.length, 1);
      expect(byTitle.songs.first.title, '稻香');

      // 按歌手搜索
      final byArtist = await source.search(keyword: '周杰伦');
      expect(byArtist.songs.length, 2);

      // 搜索无结果
      final noMatch = await source.search(keyword: '不存在的歌');
      expect(noMatch.songs, isEmpty);

      await tempDir.delete(recursive: true);
    });

    test('getSongUrl 返回 localPath', () async {
      final tempDir = await Directory.systemTemp.createTemp('resonance_url_');
      final file = File('${tempDir.path}/artist - title.mp3');
      await file.writeAsBytes([0x00]);

      await source.init();
      await source.scanDirectory(tempDir.path);

      final songs = source.getScannedSongs();
      final url = await source.getSongUrl(songs.first.id);
      expect(url, endsWith('artist - title.mp3'));

      await tempDir.delete(recursive: true);
    });

    test('getSongDetail 返回歌曲信息', () async {
      final tempDir = await Directory.systemTemp.createTemp('resonance_detail_');
      await File('${tempDir.path}/周杰伦 - 稻香.mp3').writeAsBytes([0x00]);

      await source.init();
      await source.scanDirectory(tempDir.path);

      final songs = source.getScannedSongs();
      final detail = await source.getSongDetail(songs.first.id);
      expect(detail.title, '稻香');
      expect(detail.artist, '周杰伦');

      await tempDir.delete(recursive: true);
    });

    test('getSongDetail 不存在的 id 抛异常', () async {
      await source.init();
      expect(() => source.getSongDetail('nonexistent'), throwsException);
    });

    test('clear 清除所有扫描结果', () async {
      final tempDir = await Directory.systemTemp.createTemp('resonance_clear_');
      await File('${tempDir.path}/a - b.mp3').writeAsBytes([0x00]);

      await source.init();
      await source.scanDirectory(tempDir.path);
      expect(source.getScannedSongs().length, 1);

      await source.clear();
      expect(source.getScannedSongs(), isEmpty);

      await tempDir.delete(recursive: true);
    });

    test('loadFromDatabase 恢复已扫描歌曲', () async {
      final tempDir = await Directory.systemTemp.createTemp('resonance_load_');
      await File('${tempDir.path}/周杰伦 - 稻香.mp3').writeAsBytes([0x00]);

      // 第一次扫描并存入数据库
      await source.init();
      await source.scanDirectory(tempDir.path);
      expect(source.getScannedSongs().length, 1);

      // 创建新实例，从数据库恢复
      final source2 = LocalScanSource(db.songDao);
      await source2.init();
      await source2.loadFromDatabase();
      expect(source2.getScannedSongs().length, 1);
      expect(source2.getScannedSongs().first.title, '稻香');

      await tempDir.delete(recursive: true);
    });

    test('不存在的目录抛异常', () async {
      await source.init();
      expect(
        () => source.scanDirectory('/nonexistent/path/xyz'),
        throwsArgumentError,
      );
    });

    test('支持多种音频格式', () async {
      final tempDir = await Directory.systemTemp.createTemp('resonance_formats_');
      await File('${tempDir.path}/a.mp3').writeAsBytes([0x00]);
      await File('${tempDir.path}/b.flac').writeAsBytes([0x00]);
      await File('${tempDir.path}/c.aac').writeAsBytes([0x00]);
      await File('${tempDir.path}/d.wav').writeAsBytes([0x00]);
      await File('${tempDir.path}/e.m4a').writeAsBytes([0x00]);
      await File('${tempDir.path}/f.ogg').writeAsBytes([0x00]);
      await File('${tempDir.path}/g.opus').writeAsBytes([0x00]);
      // 非音频文件
      await File('${tempDir.path}/h.txt').writeAsBytes([0x00]);
      await File('${tempDir.path}/i.jpg').writeAsBytes([0x00]);

      await source.init();
      final count = await source.scanDirectory(tempDir.path);
      expect(count, 7); // 7 种音频格式，排除 txt 和 jpg

      await tempDir.delete(recursive: true);
    });

    test('getLyrics 读取同名 .lrc 文件', () async {
      final tempDir = await Directory.systemTemp.createTemp('resonance_lrc_');
      // 创建音频 + 同名 lrc
      final audioPath = '${tempDir.path}/周杰伦 - 晴天.mp3';
      await File(audioPath).writeAsBytes([0x00]);
      await File('${tempDir.path}/周杰伦 - 晴天.lrc').writeAsString('''
[ti:晴天]
[ar:周杰伦]
[00:12.00]故事的小黄花
[00:16.00]从出生那年就飘着
''');

      await source.init();
      await source.scanDirectory(tempDir.path);

      final songs = source.getScannedSongs();
      final lyrics = await source.getLyrics(songs.first.id);

      expect(lyrics, isNotNull);
      expect(lyrics!.songId, songs.first.id);
      expect(lyrics.sourceId, 'local_scan');
      expect(lyrics.lines.length, 2);
      expect(lyrics.lines.first.text, '故事的小黄花');
      expect(lyrics.lines.first.time, const Duration(seconds: 12));

      await tempDir.delete(recursive: true);
    });

    test('getLyrics 无 .lrc 文件返回 null', () async {
      final tempDir = await Directory.systemTemp.createTemp('resonance_nolrc_');
      await File('${tempDir.path}/周杰伦 - 晴天.mp3').writeAsBytes([0x00]);

      await source.init();
      await source.scanDirectory(tempDir.path);

      final songs = source.getScannedSongs();
      final lyrics = await source.getLyrics(songs.first.id);
      expect(lyrics, isNull);

      await tempDir.delete(recursive: true);
    });

    test('getLyrics 不存在的歌曲返回 null', () async {
      await source.init();
      final lyrics = await source.getLyrics('nonexistent');
      expect(lyrics, isNull);
    });
  });
}
