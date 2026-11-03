// GD音乐台（网易云）规则源真实 API 测试
//
// 真实网络、无 mock：覆盖搜索 / 分页 / 播放地址 / 封面 / 双语歌词。
//
// 两条"别踩的坑"写在这里：
//   ① 源站限流 50 次/5 分钟。本次实测：5 分钟内请求过量后，搜索会返回
//      **空数组**（HTTP 仍为 200），几分钟后同一请求恢复正常 —— 看起来很像规则失效。
//      所以全文件共用一次搜索（[pageOne]），每条用例不再各搜一次；
//      逐个取详情/歌词的循环也限制在 3 首以内，避免把配额吃光。
//   ② 源侧不是每首曲子都给地址/封面（下架、VIP 会返回空 url），
//      因此断言写成"在若干结果里找到第一个可用的"，不把源的正常波动当引擎缺陷。

import 'dart:io';

import 'package:core/core.dart';
import 'package:crawler/crawler.dart';
import 'package:test/test.dart';

void main() {
  late RuleConfig ruleConfig;
  late RuleBasedMusicSource source;

  /// 全文件共用的第 1 页搜索结果（只发一次请求，省配额）
  late Future<SearchResult> pageOneFuture;
  SearchResult? pageOneCache;

  Future<SearchResult> pageOne() async =>
      pageOneCache ??= await pageOneFuture;

  setUpAll(() {
    // 与 App 加载的是同一份规则文件，避免"测试用别的规则"这种假绿
    final file = File('../../resonance_app/assets/rules/gdstudio_netease.json');
    ruleConfig = RuleLoader.loadFromJson(file.readAsStringSync())!;
    source = RuleBasedMusicSource(ruleConfig);
    pageOneFuture = source.search(keyword: '告白气球', page: 1);
  });

  group('GD音乐台·网易云 规则源', () {
    test('规则配置：复合 ID 拆分 + 歌词译文都配上了', () {
      expect(ruleConfig.source.id, equals('gdstudio_netease'));
      expect(ruleConfig.source.baseUrl, contains('music-api.gdstudio.xyz'));
      expect(ruleConfig.search, isNotNull);
      // 详情两跳：先封面（可选，失败不毁播放）再播放地址
      expect(ruleConfig.songDetail!.steps!.length, equals(2));
      expect(ruleConfig.songDetail!.steps!.first.optional, isTrue);
      expect(ruleConfig.songDetail!.params!['picId'], isNotEmpty);
      // 歌词节点要拆复合 ID，并配了译文
      expect(ruleConfig.lyric!.params!['id'], isNotEmpty);
      expect(ruleConfig.lyric!.translationRule, equals(r'$.tlyric'));
      print('\n✅ 规则加载: ${ruleConfig.source.name}');
    });

    test('搜索返回真实曲目，ID 为 trackId~picId 复合格式', () async {
      final result = await pageOne();

      expect(result.songs, isNotEmpty, reason: '空结果多为触发限流，稍后重跑');
      expect(result.sourceId, equals('gdstudio_netease'));
      expect(result.songs.length, equals(20), reason: 'count=20');
      expect(result.hasMore, isTrue);
      expect(result.nextPage, equals(2));

      final song = result.songs.first;
      expect(song.title, isNotEmpty);
      expect(song.artist, isNotEmpty);
      // 复合 ID 是"详情能同时拿到播放地址与封面"的前提
      expect(song.id, contains('~'));
      for (final part in song.id.split('~')) {
        expect(part, isNotEmpty, reason: 'trackId/picId 都不该为空');
      }

      print('\n🎵 搜索结果 (${result.songs.length} 首):');
      for (var i = 0; i < 3; i++) {
        final s = result.songs[i];
        print('   ${i + 1}. ${s.title} - ${s.artist} (id: ${s.id})');
      }
    });

    test('分页：第 2 页与第 1 页不同；冷门词没有更多', () async {
      final first = await pageOne();
      final page2 = await source.search(keyword: '告白气球', page: 2);
      expect(page2.songs, isNotEmpty);
      expect(page2.songs.first.id, isNot(equals(first.songs.first.id)));

      final rare = await source.search(keyword: 'zzxqwertyuiopasdf', page: 1);
      expect(rare.songs.length, lessThan(20));
      expect(rare.hasMore, isFalse);
      print('\n📄 第 2 页首条: ${page2.songs.first.title}；冷门词 ${rare.songs.length} 首');
    });

    test('播放地址：前 3 首里至少一首拿到 CDN 直链', () async {
      final result = await pageOne();
      String? url;
      Song? hit;
      for (final song in result.songs.take(3)) {
        final candidate = await source.getSongUrl(song.id);
        if (candidate.isNotEmpty) {
          url = candidate;
          hit = song;
          break;
        }
      }

      expect(url, isNotNull, reason: '前 3 首都没有播放地址，说明接口或规则有问题');
      expect(url!.startsWith('http'), isTrue);
      print('\n🎧 ${hit!.title} → $url');
    });

    test('封面：详情顺带取回封面 URL（params 拆出 picId）', () async {
      final result = await pageOne();
      String? cover;
      for (final song in result.songs.take(3)) {
        final playable = await source.getPlayable(song.id);
        final candidate = playable.meta?.coverUrl ?? '';
        if (candidate.isNotEmpty) {
          cover = candidate;
          break;
        }
      }

      expect(cover, isNotNull,
          reason: '前 3 首都取不到封面：复合 ID 拆分或封面步骤失效');
      expect(cover!.startsWith('http'), isTrue);
      print('\n🖼 封面: $cover');
    });

    test('歌词：返回可解析的 LRC 行', () async {
      final result = await pageOne();
      final lyrics = await source.getLyrics(result.songs.first.id);

      expect(lyrics, isNotNull);
      expect(lyrics!.lines, isNotEmpty);
      expect(lyrics.lines.first.text, isNotEmpty);
      print('\n📝 歌词 ${lyrics.lines.length} 行，首行: ${lyrics.lines.first.text}');
    });

    test('双语歌词：英文曲目的译文并进同一行（不是整块堆在末尾）', () async {
      // 网易云对多数英文曲目提供 tlyric 中文译文
      final result = await source.search(keyword: 'Shape of You', page: 1);
      expect(result.songs, isNotEmpty, reason: '空结果多为触发限流，稍后重跑');

      var merged = false;
      var checked = 0;
      for (final song in result.songs.take(3)) {
        final lyrics = await source.getLyrics(song.id);
        if (lyrics == null || lyrics.lines.isEmpty) continue;
        checked++;
        if (lyrics.lines.any((line) => line.text.contains(' / '))) {
          merged = true;
          final sample = lyrics.lines.firstWhere((l) => l.text.contains(' / '));
          print('\n🌏 ${song.title}: ${sample.text}');
          break;
        }
      }

      expect(checked, greaterThan(0), reason: '前 3 首都没歌词，无法验证合并');
      expect(merged, isTrue,
          reason: '译文没有按时间戳合并（源侧译文若有变化，规则/引擎需要复查）');
    });
  });
}
