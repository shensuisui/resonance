// 枫叶音乐规则源真实 API 测试
//
// 测试完整流程：加载规则 → 搜索 → 获取播放 URL → 获取歌词
// 使用真实 API，无 mock

import 'dart:io';
import 'package:test/test.dart';
import 'package:core/core.dart';
import 'package:crawler/crawler.dart';

void main() {
  late RuleConfig ruleConfig;
  late RuleBasedMusicSource source;

  setUpAll(() {
    // 加载规则文件（从 fm_app/assets/rules/ 读取）
    final file = File('../../fm_app/assets/rules/fengye.json');
    final json = file.readAsStringSync();
    ruleConfig = RuleLoader.loadFromJson(json)!;
    source = RuleBasedMusicSource(ruleConfig);
  });

  group('枫叶音乐规则源', () {
    test('规则配置正确加载', () {
      expect(ruleConfig.source.id, equals('fengye'));
      expect(ruleConfig.source.name, equals('枫叶音乐'));
      expect(ruleConfig.source.baseUrl, contains('fy-musicbox-api'));
      expect(ruleConfig.search, isNotNull);
      expect(ruleConfig.songDetail, isNotNull);
      expect(ruleConfig.songDetail!.responseType, equals('redirect'));
      expect(ruleConfig.lyric, isNotNull);
    });

    test('搜索返回真实歌曲', () async {
      final result = await source.search(keyword: '周杰伦', page: 1);

      // 应返回多首歌曲
      expect(result.songs, isNotEmpty);
      expect(result.sourceId, equals('fengye'));

      // 验证歌曲字段完整性
      final song = result.songs.first;
      expect(song.id, isNotEmpty);
      expect(song.title, isNotEmpty);
      expect(song.artist, contains('周杰伦'));
      expect(song.sourceId, equals('fengye'));

      // 打印前 5 首歌曲
      print('\n🎵 搜索结果 (${result.songs.length} 首):');
      for (var i = 0; i < result.songs.length && i < 5; i++) {
        final s = result.songs[i];
        print('   ${i + 1}. ${s.title} - ${s.artist} (id: ${s.id})');
      }
    });

    test('获取播放 URL — 重定向解析', () async {
      // 先搜索获取歌曲 ID
      final searchResult = await source.search(keyword: '晴天 周杰伦', page: 1);
      expect(searchResult.songs, isNotEmpty);

      final song = searchResult.songs.first;
      print('\n🎵 获取播放 URL: ${song.title} (id: ${song.id})');

      // 获取播放 URL — 应该是真实 CDN 地址
      final url = await source.getSongUrl(song.id);

      expect(url, isNotEmpty);
      expect(url, isNot(contains('meting'))); // 不应是重定向 URL，应是 CDN 地址
      expect(url.startsWith('http'), isTrue);

      print('   ✅ 播放 URL: $url');
    });

    test('获取歌词', () async {
      // 先搜索获取歌曲 ID
      final searchResult = await source.search(keyword: '晴天 周杰伦', page: 1);
      expect(searchResult.songs, isNotEmpty);

      final song = searchResult.songs.first;
      print('\n📝 获取歌词: ${song.title} (id: ${song.id})');

      // 获取歌词
      final lyrics = await source.getLyrics(song.id);

      expect(lyrics, isNotNull);
      expect(lyrics!.lines, isNotEmpty);

      // 验证 LRC 格式（带时间戳）
      final firstLine = lyrics.lines.first;
      expect(firstLine.time.inMilliseconds, greaterThanOrEqualTo(0));
      expect(firstLine.text, isNotEmpty);

      print('   ✅ 歌词 ${lyrics.lines.length} 行');
      // 打印前 3 行歌词
      for (var i = 0; i < lyrics.lines.length && i < 3; i++) {
        final line = lyrics.lines[i];
        final min = (line.time.inMinutes).toString().padLeft(2, '0');
        final sec = (line.time.inSeconds % 60).toString().padLeft(2, '0');
        print('   [$min:$sec] ${line.text}');
      }
    });

    test('完整流程：搜索 → 播放 URL → 歌词', () async {
      print('\n========== 枫叶音乐完整流程 ==========');

      // 1. 搜索
      print('🔍 搜索: 周杰伦');
      final searchResult = await source.search(keyword: '周杰伦', page: 1);
      expect(searchResult.songs, isNotEmpty);
      final song = searchResult.songs.first;
      print('   ✅ ${searchResult.songs.length} 首歌，首首: ${song.title} - ${song.artist}');

      // 2. 播放 URL
      print('🎵 获取播放 URL: ${song.title}');
      final url = await source.getSongUrl(song.id);
      expect(url, isNotEmpty);
      print('   ✅ $url');

      // 3. 歌词
      print('📝 获取歌词: ${song.title}');
      final lyrics = await source.getLyrics(song.id);
      expect(lyrics, isNotNull);
      expect(lyrics!.lines, isNotEmpty);
      print('   ✅ ${lyrics.lines.length} 行歌词');

      print('========== 完整流程完成 ==========\n');
    });

    test('分页：第 1 页 hasMore=true，nextPage=2', () async {
      final result = await source.search(keyword: '周杰伦', page: 1);
      expect(result.songs.length, equals(20)); // limit=20
      expect(result.hasMore, isTrue, reason: '20 条应推断有更多');
      expect(result.nextPage, equals(2));
      print('\n📄 第 1 页: ${result.songs.length} 首, hasMore=${result.hasMore}, nextPage=${result.nextPage}');
    });

    test('分页：第 2 页结果与第 1 页不同', () async {
      final page1 = await source.search(keyword: '周杰伦', page: 1);
      final page2 = await source.search(keyword: '周杰伦', page: 2);
      expect(page1.songs, isNotEmpty);
      expect(page2.songs, isNotEmpty);
      // 两页的第一首不应相同
      expect(page2.songs.first.id, isNot(equals(page1.songs.first.id)),
          reason: '第 2 页应有不同结果');
      print('\n📄 第 1 页首首: ${page1.songs.first.title}');
      print('   第 2 页首首: ${page2.songs.first.title}');
    });

    test('分页：冷门关键词最后一页 hasMore=false', () async {
      // 用一个结果很少的关键词搜索
      final result = await source.search(keyword: 'asdfqwerzxcv', page: 1);
      // 结果应 < 20，hasMore=false
      expect(result.songs.length, lessThan(20));
      expect(result.hasMore, isFalse, reason: '不足 20 条，不应有更多');
      print('\n📄 冷门搜索: ${result.songs.length} 首, hasMore=${result.hasMore}');
    });
  });

  group('枫叶音乐歌单功能', () {
    test('推荐歌单列表 — 返回歌单，ID 为复合格式', () async {
      print('\n📋 获取推荐歌单列表');
      final playlists = await source.getPlaylistList();

      expect(playlists, isNotEmpty, reason: '应返回推荐歌单');

      // 验证歌单 ID 为复合格式 server-id
      final first = playlists.first;
      expect(first.id, contains('-'), reason: 'ID 应为 server-id 复合格式');
      expect(first.name, isNotEmpty);
      expect(first.sourceId, equals('fengye'));
      expect(first.coverUrl, isNotEmpty,
          reason: '推荐歌单应能提取封面 URL（发现页图片依赖此字段）');

      print('   ✅ ${playlists.length} 个歌单');
      for (var i = 0; i < playlists.length && i < 5; i++) {
        final p = playlists[i];
        print('   ${i + 1}. ${p.name} (id: ${p.id}) cover: ${p.coverUrl}');
      }

      // 缓存第一个歌单 ID 供后续测试
      _cachedPlaylistId = playlists.first.id;
      _cachedPlaylistName = playlists.first.name;
    });

    test('歌单详情 — params 拆分复合 ID，返回元数据和曲目', () async {
      // 确保有缓存的歌单 ID
      expect(_cachedPlaylistId, isNotNull, reason: '需先运行歌单列表测试');

      print('\n📋 获取歌单详情: $_cachedPlaylistId ($_cachedPlaylistName)');
      final playlist = await source.getPlaylist(_cachedPlaylistId!);

      expect(playlist, isNotNull, reason: '歌单详情不应为空');
      expect(playlist!.name, isNotEmpty, reason: '歌单名称应从 playlistInfo 提取');
      expect(playlist.songKeys, isNotEmpty, reason: '歌单应有曲目');
      expect(playlist.sourceId, equals('fengye'));

      print('   ✅ 歌单名: ${playlist.name}');
      print('   ✅ 曲目数: ${playlist.songKeys.length}');
      print('   ✅ 封面: ${playlist.coverUrl ?? "(无)"}');
    });

    test('播放请求头 — playHeaders 返回 referer', () {
      print('\n🎵 播放请求头');
      final headers = source.playHeaders;

      expect(headers, isNotEmpty, reason: '应有播放请求头');
      expect(headers, containsPair('referer', 'https://mu-jie.cc/'));

      print('   ✅ $headers');
    });
  });
}

// 跨测试缓存的歌单信息
String? _cachedPlaylistId;
String? _cachedPlaylistName;
