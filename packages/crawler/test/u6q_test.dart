import 'dart:convert';
import 'dart:io';
import 'package:crawler/crawler.dart';
import 'package:expr/expr.dart';
import 'package:flutter_test/flutter_test.dart';

/// 6uq.cn 规则文件测试
///
/// 测试目标：
/// 1. 规则文件 JSON 解析正确
/// 2. CSS + regex 链式表达式提取 ID/标题/歌手
/// 3. Preflight 配置（CSRF 流程）
/// 4. 真实 API 完整流程（搜索 → 播放URL → 歌词）
void main() {
  group('6uq.cn 规则配置解析', () {
    late RuleConfig config;

    setUpAll(() {
      // 从规则文件加载配置
      final file = File('../../fm_app/assets/rules/6uq.json');
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      config = RuleConfig.fromJson(json);
    });

    test('源信息正确', () {
      expect(config.source.id, '6uq');
      expect(config.source.name, '6U音乐');
      expect(config.source.baseUrl, 'http://www.6uq.cn');
    });

    test('preflight 配置正确', () {
      final preflight = config.preflight!;
      expect(preflight.steps.length, 2);
      expect(preflight.cacheMinutes, 50);

      // Step 1: GET / 提取 csrf_token
      final step1 = preflight.steps[0];
      expect(step1.method, 'GET');
      expect(step1.url, '/');
      expect(step1.responseType, 'html');
      expect(step1.extract, isNotNull);
      expect(step1.extract!['csrf_token'], contains('@CSS:'));
      expect(step1.extract!['csrf_token'], contains('csrf_token'));
      expect(step1.extract!['csrf_token'], contains('@value'));

      // Step 2: POST / 提交 CSRF token
      final step2 = preflight.steps[1];
      expect(step2.method, 'POST');
      expect(step2.url, '/');
      expect(step2.body, contains('csrf_token={csrf_token}'));
      expect(step2.body, contains('human_check=on'));
      expect(step2.contentType, 'application/x-www-form-urlencoded');
    });

    test('搜索配置正确', () {
      final search = config.search!;
      expect(search.url, '/so/{keyword}.html');
      expect(search.responseType, 'html');
      expect(search.listRule, contains('ul li'));

      // ID 提取：CSS href + regex 链式
      expect(search.itemRules['id'], contains('@CSS:'));
      expect(search.itemRules['id'], contains('@href'));
      expect(search.itemRules['id'], contains('&&'));
      expect(search.itemRules['id'], contains('@Regex:'));

      // 标题提取：《标题》正则
      expect(search.itemRules['title'], contains('《'));

      // 歌手提取：非《开头的文本
      expect(search.itemRules['artist'], contains('^[^《'));

      // 分页：size 类型
      expect(search.pagination, isNotNull);
      expect(search.pagination!.type, 'size');
      expect(search.pagination!.limitValue, 20);
    });

    test('播放URL配置正确（redirect 类型）', () {
      final detail = config.songDetail!;
      expect(detail.url, contains('/plug/down.php'));
      expect(detail.url, contains('ac=music'));
      expect(detail.url, contains('id={id}'));
      expect(detail.url, contains('k=320kmp3'));
      expect(detail.responseType, 'redirect');
    });

    test(r'歌词配置正确（JSON $.lrc）', () {
      final lyric = config.lyric!;
      expect(lyric.url, contains('/plug/lrcgc.php'));
      expect(lyric.url, contains('id={id}'));
      expect(lyric.responseType, 'json');
      expect(lyric.contentRule, r'$.lrc');
    });
  });

  group('CSS + regex 链式表达式', () {
    // 模拟 6uq.cn 搜索结果 HTML
    const html = '''
<html><body>
<ul>
  <li>
    <div class="name"><a href="/play/dndmeWJreQ.html">周杰伦《稻香》[MP3_LRC]</a></div>
    <div class="mv"><a href="/video/dndmeWJreQ.html">mv</a></div>
  </li>
  <li>
    <div class="name"><a href="/play/dndtZWpqRQ.html">郭静《临界点》[MP3_LRC]</a></div>
    <div class="mv"><a href="/video/dndtZWpqRQ.html">mv</a></div>
  </li>
</ul>
</body></html>
''';

    test('提取列表项', () {
      initExprEngine();
      final items = ResponseHandler.extractList(html, r"@CSS:ul li@html");
      expect(items.length, 2);
    });

    test('链式表达式提取歌曲 ID', () {
      initExprEngine();
      final items = ResponseHandler.extractList(html, r"@CSS:ul li@html");
      final item = items.first as String;

      // 链式：CSS @href → regex 提取 ID
      final id = evaluate(r"@CSS:div.name a@href && @Regex:/play/([^.]+)", item);
      expect(id, isNotNull);
      expect(id.toString(), isNot(contains('[')));
      expect(id, 'dndmeWJreQ');
    });

    test('链式表达式提取标题', () {
      initExprEngine();
      final items = ResponseHandler.extractList(html, r"@CSS:ul li@html");
      final item = items.first as String;

      // 链式：CSS @text → regex 提取《标题》
      final title = evaluate(r"@CSS:div.name a@text && @Regex:《([^》]+)》", item);
      expect(title, '稻香');
    });

    test('链式表达式提取歌手', () {
      initExprEngine();
      final items = ResponseHandler.extractList(html, r"@CSS:ul li@html");
      final item = items.first as String;

      // 链式：CSS @text → regex 提取《前部分
      final artist = evaluate(r"@CSS:div.name a@text && @Regex:^[^《]+", item);
      expect(artist, '周杰伦');
    });

    test('第二首歌提取完整', () {
      initExprEngine();
      final items = ResponseHandler.extractList(html, r"@CSS:ul li@html");
      final item = items[1] as String;

      final id = evaluate(r"@CSS:div.name a@href && @Regex:/play/([^.]+)", item);
      final title = evaluate(r"@CSS:div.name a@text && @Regex:《([^》]+)》", item);
      final artist = evaluate(r"@CSS:div.name a@text && @Regex:^[^《]+", item);

      expect(id, 'dndtZWpqRQ');
      expect(title, '临界点');
      expect(artist, '郭静');
    });

    test('完整 extractItem 返回结构化数据', () {
      initExprEngine();
      final items = ResponseHandler.extractList(html, r"@CSS:ul li@html");

      final result = ResponseHandler.extractItem(items.first, {
        'id': r"@CSS:div.name a@href && @Regex:/play/([^.]+)",
        'title': r"@CSS:div.name a@text && @Regex:《([^》]+)》",
        'artist': r"@CSS:div.name a@text && @Regex:^[^《]+",
      });

      expect(result['id'], 'dndmeWJreQ');
      expect(result['title'], '稻香');
      expect(result['artist'], '周杰伦');
    });
  });

  group('真实 API 流程', () {
    late RuleConfig config;

    setUpAll(() {
      final file = File('../../fm_app/assets/rules/6uq.json');
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      config = RuleConfig.fromJson(json);
    });

    test(
      '搜索 郭静 → 返回结果',
      () async {
        final source = RuleBasedMusicSource(config);
        final result = await source.search(keyword: '郭静');

        // 预期搜索返回多首歌曲
        expect(result.songs.length, greaterThan(0),
            reason: '搜索郭静应返回多首歌曲');
        expect(result.songs.first.title, isNotEmpty);
        expect(result.songs.first.artist, isNotEmpty);
        expect(result.songs.first.id, isNotEmpty);

        print('搜索结果 (${result.songs.length} 首):');
        for (final song in result.songs.take(5)) {
          print('  - ${song.title} - ${song.artist} (id: ${song.id})');
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
      skip: '需要真实网络环境，CI 中跳过',
    );

    test(
      '搜索 → 播放URL → 歌词 完整流程',
      () async {
        final source = RuleBasedMusicSource(config);

        // 1. 搜索
        final searchResult = await source.search(keyword: '郭静');
        expect(searchResult.songs, isNotEmpty,
            reason: '搜索应返回结果');
        final song = searchResult.songs.first;
        print('搜索: ${song.title} - ${song.artist} (id: ${song.id})');

        // 2. 获取播放 URL
        final playUrl = await source.getSongUrl(song.id);
        print('播放URL: $playUrl');
        expect(playUrl, isNotEmpty, reason: '应返回有效的播放 URL');
        expect(playUrl, contains('.mp3'),
            reason: '播放 URL 应指向 MP3 文件');

        // 3. 获取歌词
        final lyrics = await source.getLyrics(song.id);
        expect(lyrics, isNotNull, reason: '应返回歌词');
        expect(lyrics!.lines, isNotEmpty, reason: '歌词行数应大于 0');
        print('歌词: ${lyrics.lines.length} 行');
        expect(lyrics.lines.first.text, isNotEmpty);
      },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: '需要真实网络环境，CI 中跳过',
    );
  });
}
