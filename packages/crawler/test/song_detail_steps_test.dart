/// 多步 songDetail（steps）与相关解析的回归测试
///
/// 背景：歌曲宝（gequbao）取播放地址必须两步——先 GET 详情页拿到服务端加密的
/// play_id，再 POST /member/common-play-url 换真实地址。传统 songDetail 是单请求，
/// 无法表达，因此引擎新增了 steps（复用 preflight 的多步 + extract 能力）。
///
/// 这里覆盖：
///   * steps 规则解析
///   * 两步取播放地址 + 变量注入（URL / body / headers）
///   * 步骤 extract 到的字段（封面、标题、时长）与函数返回值合并
///   * mm:ss 文本时长转秒（"03:29" → 209）
///   * contentRule 返回列表时取首元素（否则 toString 会变成 "[歌词]"）
///   * 旧的单请求 songDetail 写法不受影响
library;

import 'dart:convert';
import 'dart:io';

import 'package:crawler/crawler.dart';
import 'package:test/test.dart';

void main() {
  group('多步 songDetail 规则解析', () {
    test('解析 steps 与末步的 listRule/itemRules', () {
      final config = RuleConfig.fromJson({
        'source': {'id': 'x', 'name': 'X'},
        'songDetail': {
          'steps': [
            {
              'url': '/a/{id}',
              'responseType': 'html',
              'extract': {'pid': r'@Regex:p=([0-9]+)'},
            },
            {
              'url': '/b',
              'method': 'POST',
              'responseType': 'json',
              'body': 'id={pid}',
              'listRule': r'$',
              'itemRules': {'playUrl': r'$.data.url'},
            },
          ],
        },
      });

      expect(config.songDetail, isNotNull);
      expect(config.songDetail!.steps!.length, 2);
      expect(config.songDetail!.steps![0].extract!['pid'], r'@Regex:p=([0-9]+)');
      expect(config.songDetail!.steps![1].body, 'id={pid}');
      expect(config.songDetail!.steps![1].listRule, r'$');
      expect(config.songDetail!.steps![1].itemRules!['playUrl'], r'$.data.url');
    });

    test('未配置 steps 时保持单请求（steps 为 null）', () {
      final config = RuleConfig.fromJson({
        'source': {'id': 'x', 'name': 'X'},
        'songDetail': {
          'url': '/song/{id}',
          'responseType': 'json',
          'listRule': r'$',
          'itemRules': {'playUrl': r'$.url'},
        },
      });
      expect(config.songDetail!.steps, isNull);
    });
  });

  group('多步 songDetail 真实 HTTP 桩', () {
    late HttpServer server;
    late int port;

    /// 服务端加密的 play_id（这里用等长 base64 字符模拟）
    late String playId;

    /// 服务端收到的 POST 报文与 Referer，用于断言变量注入
    String? postedBody;
    String? postedReferer;

    setUp(() async {
      playId = List<String>.filled(288, 'A').join();
      postedBody = null;
      postedReferer = null;

      server = await HttpServer.bind('localhost', 0);
      port = server.port;

      server.listen((request) async {
        final path = request.uri.path;
        final res = request.response;

        if (path == '/music/123' && request.method == 'GET') {
          // 模拟歌曲宝详情页：appData 里的字段用 \u0022 转义，和真实页面一致
          final html = '<html><body>'
              '<h1 class="song-title-styled"><span>真的爱你又如何</span></h1>'
              '<div class="song-author-styled"> 王一佳 </div>'
              '<img class="player-cover-img" src="http://localhost:$port/cover/a.jpg">'
              '<div class="content-lrc" id="content-lrc">[00:00.00]词：张<br />[00:10.47]你听不见我在说什么</div>'
              '<script>window.appData = JSON.parse(\'{'
              '\\u0022mp3_id\\u0022:123,'
              '\\u0022play_id\\u0022:\\u0022$playId\\u0022,'
              '\\u0022mp3_duration\\u0022:\\u002203:29\\u0022'
              '}\');</script>'
              '</body></html>';
          res
            ..statusCode = 200
            ..headers.contentType = ContentType.html
            ..write(html);
        } else if (path == '/member/common-play-url' &&
            request.method == 'POST') {
          postedBody = await utf8.decoder.bind(request).join();
          postedReferer = request.headers.value('referer');
          res
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({
              'code': 1,
              'data': {'url': 'http://localhost:$port/audio/a.mp3?bitrate=128'},
            }));
        } else if (path == '/legacy/song/123' && request.method == 'GET') {
          res
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'url': 'http://localhost:$port/audio/legacy.mp3'}));
        } else {
          res.statusCode = 404;
        }
        await res.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('两步取播放地址：变量注入 URL/body/headers 且字段与变量池合并', () async {
      final config = RuleConfig.fromJson({
        'source': {
          'id': 'gqb',
          'name': 'GQB',
          'baseUrl': 'http://localhost:$port',
        },
        'songDetail': {
          'steps': [
            {
              'url': '/music/{id}',
              'responseType': 'html',
              'extract': {
                // 显式匹配转义包裹，否则惰性量词会把 \u0022 的 u0022 吞进捕获组
                'playId': r'@Regex:play_id\\u0022:\\u0022([A-Za-z0-9+/=]{100,})',
                'title': r'@CSS:h1.song-title-styled span@text',
                'artist': r'@CSS:div.song-author-styled@text',
                'coverUrl': r'@CSS:img.player-cover-img@src',
                'duration': r'@Regex:mp3_duration.{0,20}([0-9]{1,2}:[0-9]{2})',
              },
            },
            {
              'url': '/member/common-play-url',
              'method': 'POST',
              'responseType': 'json',
              'contentType': 'application/x-www-form-urlencoded',
              'headers': {
                'X-Requested-With': 'XMLHttpRequest',
                'Referer': 'http://localhost:$port/music/{id}',
              },
              'body': 'id={playId}&purpose=play',
              'listRule': r'$',
              'itemRules': {'playUrl': r'$.data.url'},
            },
          ],
        },
      });

      final source = RuleBasedMusicSource(config);

      final url = await source.getSongUrl('123');
      expect(url, 'http://localhost:$port/audio/a.mp3?bitrate=128');

      // 变量注入：body 必须恰好是 id=<playId>&purpose=play
      // （用等值断言而不是 contains：后者会放过 "u0022<playId>" 这种被污染的捕获）
      expect(postedBody, 'id=' + playId + '&purpose=play');
      expect(postedReferer, 'http://localhost:$port/music/123');

      // 字段合并：extract 出来的封面/标题/时长直接当详情字段用
      final song = await source.getSongDetail('123');
      expect(song.title, '真的爱你又如何');
      expect(song.artist, '王一佳');
      expect(song.coverUrl, 'http://localhost:$port/cover/a.jpg');
      expect(song.duration, 209, reason: '"03:29" 应解析为 209 秒');
      expect(song.playUrl, 'http://localhost:$port/audio/a.mp3?bitrate=128');
    });

    test('旧的单请求 songDetail 写法不受影响', () async {
      final config = RuleConfig.fromJson({
        'source': {
          'id': 'legacy',
          'name': 'Legacy',
          'baseUrl': 'http://localhost:$port',
        },
        'songDetail': {
          'url': '/legacy/song/{id}',
          'responseType': 'json',
          'listRule': r'$',
          'itemRules': {'playUrl': r'$.url'},
        },
      });

      final source = RuleBasedMusicSource(config);
      final url = await source.getSongUrl('123');
      expect(url, 'http://localhost:$port/audio/legacy.mp3');
    });

    test('歌词：CSS @html 取首元素并把 <br /> 换成换行', () async {
      final config = RuleConfig.fromJson({
        'source': {
          'id': 'gqb',
          'name': 'GQB',
          'baseUrl': 'http://localhost:$port',
        },
        'lyric': {
          'url': '/music/{id}',
          'responseType': 'html',
          'contentRule': '@CSS:div#content-lrc@html##<br\\s*/?>||\\n',
        },
      });

      final source = RuleBasedMusicSource(config);
      final lyrics = await source.getLyrics('123');

      expect(lyrics, isNotNull);
      expect(lyrics!.isLrc, isTrue);
      expect(lyrics.lines.length, 2, reason: '两行歌词');
      expect(lyrics.lines.first.text, contains('词：张'));
      expect(lyrics.lines.first.text, isNot(contains('<br')));
      expect(lyrics.lines.first.text, isNot(contains('[')));
    });
  });
}
