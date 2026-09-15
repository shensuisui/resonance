/// RuleExecutor 离线确定性测试
///
/// 手法与 preflight_test.dart / crawler_test.dart 一致：
/// 启动本地真实 HttpServer，通过 RuleBasedMusicSource 公共 API 驱动
/// RuleExecutor 的各条执行路径。不依赖外网——fengye_test / u6q_test
/// 走真实 API（受网络与第三方服务状态影响），本文件保证同样路径
/// 在 CI/离线环境下可重复验证。
///
/// 覆盖路径：
/// - songDetail responseType=redirect：302 提取 Location / 无 Location 返回空串
/// - playlist：params 链式表达式拆分复合 ID、playlistInfo 元数据提取、
///   曲目映射（songKeys/sourceId）、空曲目边界（getPlaylist → null）
/// - playlistList：${} 模板复合 ID、缺 name 条目跳过、page 参数透传
/// - lyric：text 直读解析 LRC / 无时间戳纯文本退化 / JSON contentRule 提取
/// - 搜索字段映射：缺 id/title 跳过、duration 字符串转 int、
///   未知字段进 extra、playUrl 与 url 键兼容
/// - pagination：size 数量推断、cursor 游标提取
/// - HTTP 错误容错：搜索 500 → 空结果、歌单 404 → null（均不抛异常）
///
/// 模拟数据来源：全部内联在本文件的本地 server 路由中，与真实源
/// （枫叶音乐 fengye.json）的规则结构保持一致。
library;

import 'dart:convert';
import 'dart:io';

// crawler 也导出名为 HttpResponse 的类（HTTP 客户端响应封装），
// 与 dart:io 的服务端响应类型冲突，此处测试只用 dart:io 的，隐藏之
import 'package:crawler/crawler.dart' hide HttpResponse;
import 'package:test/test.dart';

/// 统一 JSON 响应输出
void _sendJson(HttpResponse resp, Object data) {
  resp
    ..statusCode = 200
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(data))
    ..close();
}

/// 统一纯文本响应输出
void _sendText(HttpResponse resp, String text) {
  resp
    ..statusCode = 200
    ..headers.contentType = ContentType.text
    ..write(text)
    ..close();
}

void main() {
  late HttpServer server;
  late int port;

  /// 记录最近一次 /playlist 请求收到的查询参数（断言 params 拆分结果）
  Map<String, String> lastPlaylistQuery = {};

  /// 记录最近一次 /recommend 请求收到的查询参数（断言 page 透传）
  Map<String, String> lastRecommendQuery = {};

  setUp(() async {
    lastPlaylistQuery = {};
    lastRecommendQuery = {};
    server = await HttpServer.bind('localhost', 0);
    port = server.port;

    server.listen((request) {
      final uri = request.uri;
      switch (uri.path) {
        // ===== redirect 播放地址 =====
        case '/redirect':
          // 302 + Location：真实 CDN 跳转（枫叶音乐 meting 接口的行为）
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set(
                HttpHeaders.locationHeader, 'http://cdn.test/final.mp3?key=abc')
            ..close();
        case '/redirect_noloc':
          // 302 但无 Location（异常边界）
          request.response..statusCode = HttpStatus.found..close();

        // ===== 歌单详情 =====
        case '/playlist':
          lastPlaylistQuery = uri.queryParameters;
          _sendJson(request.response, {
            'name': '测试歌单',
            'coverImgUrl': 'https://example.com/pl.jpg',
            'tracks': [
              {'id': 't1', 'name': '曲一', 'artist': '歌手一'},
              {'id': 't2', 'name': '曲二', 'artist': '歌手二'},
            ],
          });
        case '/playlist_noname':
          // 无 name/coverImgUrl：playlistInfo 未配置时名称应回退为 id
          _sendJson(request.response, {
            'tracks': [
              {'id': 't1', 'name': '曲一', 'artist': 'A'},
            ],
          });
        case '/playlist_empty':
          // 空曲目边界：getPlaylist 应返回 null，getPlaylistSongs 应返回 []
          _sendJson(request.response, {'name': '空歌单', 'tracks': []});

        // ===== 推荐歌单列表 =====
        case '/recommend':
          lastRecommendQuery = uri.queryParameters;
          _sendJson(request.response, [
            {
              'server': 'netease',
              'id': '12345',
              'name': '推荐一',
              'coverImgUrl': 'http://c1',
            },
            {'server': 'qq', 'id': '999', 'name': '推荐二'},
            {'server': 'x', 'id': '1'}, // 缺 name → 应被跳过
          ]);

        // ===== 歌词 =====
        case '/lyric_text':
          _sendText(request.response, '[00:12.00]第一句\n[00:16.50]第二句');
        case '/lyric_plain':
          _sendText(request.response, '纯文本歌词无时间戳');
        case '/lyric_json':
          _sendJson(request.response, {'lrc': '[00:01.00]JSON歌词'});

        // ===== 搜索（按 keyword 路由不同数据集） =====
        case '/search':
          final kw = uri.queryParameters['keyword'] ?? '';
          switch (kw) {
            case 'fields':
              // 字段映射数据集：1 条完整 + 1 条缺 id + 1 条缺 title
              _sendJson(request.response, [
                {
                  'id': '1',
                  'name': '字段歌',
                  'artist': '歌手',
                  'duration': '240', // 字符串时长 → 应解析为 int
                  'url': 'http://play/1.mp3',
                  'vip': true, // 未知字段 → 应进 extra
                  'quality': 'flac', // 已知排除字段 → 不应进 extra
                },
                {'name': '缺id'},
                {'id': '3'},
              ]);
            case 'two':
              // 分页 size 推断：恰好等于 limitValue
              _sendJson(request.response, [
                {'id': '1', 'name': '歌一'},
                {'id': '2', 'name': '歌二'},
              ]);
            case 'one':
              // 分页 size 推断：不足 limitValue
              _sendJson(request.response, [
                {'id': '1', 'name': '歌一'},
              ]);
            case 'boom':
              // 服务端错误：搜索应吞掉异常返回空结果
              request.response
                ..statusCode = 500
                ..write('server error')
                ..close();
            default:
              _sendJson(request.response, []);
          }
        case '/search_cursor':
          // cursor 分页数据集：根对象带 nextCursor
          _sendJson(request.response, {
            'data': [
              {'id': '1', 'name': '游标歌'},
            ],
            'nextCursor': 'abc',
          });
        case '/search2':
          // url 键兼容数据集：itemRules 用 'url' 键而非 'playUrl'
          _sendJson(request.response, [
            {'id': '2', 'name': '兼容歌', 'url': 'http://u/2.mp3'},
          ]);

        default:
          request.response
            ..statusCode = 404
            ..write('{}')
            ..close();
      }
    });
  });

  tearDown(() async {
    await server.close();
  });

  /// 构造指向本地 server 的测试源（source.id 固定为 rex）
  RuleBasedMusicSource testSource(Map<String, dynamic> ruleJson) {
    return RuleBasedMusicSource(RuleConfig.fromJson({
      'source': {
        'id': 'rex',
        'name': 'RuleExecutor 测试源',
        'baseUrl': 'http://localhost:$port',
      },
      ...ruleJson,
    }));
  }

  group('songDetail redirect 重定向解析', () {
    test('302 + Location → getSongUrl 返回跳转目标', () async {
      final source = testSource({
        'songDetail': {
          'url': '/redirect?id={id}',
          'responseType': 'redirect',
          // redirect 路径不使用 listRule/itemRules，但 FlowRule 解析要求非空
          'listRule': r'$',
          'itemRules': {'playUrl': 'redirect_url'},
        },
      });
      expect(await source.getSongUrl('s1'), 'http://cdn.test/final.mp3?key=abc');
    });

    test('302 无 Location → getSongUrl 返回空串（不抛异常）', () async {
      final source = testSource({
        'songDetail': {
          'url': '/redirect_noloc?id={id}',
          'responseType': 'redirect',
          'listRule': r'$',
          'itemRules': {'playUrl': 'redirect_url'},
        },
      });
      expect(await source.getSongUrl('s1'), '');
    });
  });

  group('playlist 歌单详情', () {
    /// 与 fengye.json 相同结构的歌单规则（params 拆分复合 ID）
    Map<String, dynamic> playlistRule(String path) => {
          'playlist': {
            'url': '$path?server={server}&id={playlistId}',
            'responseType': 'json',
            'listRule': r'$.tracks',
            'itemRules': {'id': 'id', 'title': 'name', 'artist': 'artist'},
            'params': {
              // 链式表达式：先 $.id 取复合 ID，再正则拆出前/后段
              'server': r'$.id && @Regex:^[^-]+',
              'playlistId': r'$.id && @Regex:[^-]+$',
            },
            'playlistInfo': {'title': 'name', 'coverUrl': 'coverImgUrl'},
          },
        };

    test('params 链式表达式拆分复合 ID 注入 URL', () async {
      final source = testSource(playlistRule('/playlist'));
      final playlist = await source.getPlaylist('netease-12345');

      // 服务器实际收到的查询参数应是拆分后的两段
      expect(lastPlaylistQuery['server'], 'netease');
      expect(lastPlaylistQuery['id'], '12345');

      expect(playlist, isNotNull);
    });

    test('playlistInfo 提取歌单名称与封面', () async {
      final source = testSource(playlistRule('/playlist'));
      final playlist = await source.getPlaylist('netease-12345');

      expect(playlist!.name, '测试歌单');
      expect(playlist.coverUrl, 'https://example.com/pl.jpg');
      expect(playlist.id, 'netease-12345');
      expect(playlist.sourceId, 'rex');
      expect(playlist.sourcePlaylistId, 'netease-12345');
    });

    test('曲目映射为 songKeys（sourceId:id，保序）', () async {
      final source = testSource(playlistRule('/playlist'));
      final playlist = await source.getPlaylist('netease-12345');

      expect(playlist!.songKeys, ['rex:t1', 'rex:t2']);
    });

    test('getPlaylistSongs 返回完整曲目（含 sourceId/歌手）', () async {
      final source = testSource(playlistRule('/playlist'));
      final songs = await source.getPlaylistSongs('netease-12345');

      expect(songs.length, 2);
      expect(songs[0].id, 't1');
      expect(songs[0].title, '曲一');
      expect(songs[0].artist, '歌手一');
      expect(songs[0].sourceId, 'rex');
      expect(songs[1].title, '曲二');
    });

    test('未配置 playlistInfo 时名称回退为歌单 id', () async {
      final source = testSource({
        'playlist': {
          'url': '/playlist_noname',
          'responseType': 'json',
          'listRule': r'$.tracks',
          'itemRules': {'id': 'id', 'title': 'name', 'artist': 'artist'},
        },
      });
      final playlist = await source.getPlaylist('pl-9');

      expect(playlist, isNotNull);
      expect(playlist!.name, 'pl-9', reason: '无 playlistInfo 时名称=id');
      expect(playlist.coverUrl, isNull);
    });

    test('空曲目：getPlaylist 返回 null，getPlaylistSongs 返回空列表', () async {
      final source = testSource({
        'playlist': {
          'url': '/playlist_empty',
          'responseType': 'json',
          'listRule': r'$.tracks',
          'itemRules': {'id': 'id', 'title': 'name', 'artist': 'artist'},
          'playlistInfo': {'title': 'name'},
        },
      });

      // 边界：RuleBasedMusicSource.getPlaylist 对空曲目返回 null
      expect(await source.getPlaylist('empty-1'), isNull);
      // 而 getPlaylistSongs 返回空列表（不是 null）
      expect(await source.getPlaylistSongs('empty-1'), isEmpty);
    });
  });

  group('playlistList 推荐歌单列表', () {
    /// 与 fengye.json 相同结构的推荐歌单规则（模板复合 ID）
    RuleBasedMusicSource listSource() => testSource({
          'playlistList': {
            'url': '/recommend?page={page}',
            'responseType': 'json',
            'listRule': r'$',
            'itemRules': {
              'id': r'${$.server}-${$.id}', // 模板语法拼接复合 ID
              'title': 'name',
              'coverUrl': 'coverImgUrl',
            },
          },
        });

    test(r'${} 模板生成复合 ID 并提取封面', () async {
      final playlists = await listSource().getPlaylistList();

      expect(playlists.length, 2, reason: '第三条缺 name 应被跳过');
      expect(playlists[0].id, 'netease-12345');
      expect(playlists[0].name, '推荐一');
      expect(playlists[0].coverUrl, 'http://c1');
      expect(playlists[0].sourceId, 'rex');
      expect(playlists[0].sourcePlaylistId, 'netease-12345');
      // 第二条无封面字段 → coverUrl 为 null
      expect(playlists[1].id, 'qq-999');
      expect(playlists[1].coverUrl, isNull);
    });

    test('page 参数透传到 URL', () async {
      await listSource().getPlaylistList(page: 3);
      expect(lastRecommendQuery['page'], '3');
    });

    test('未配置 playlistList 时返回空列表', () async {
      expect(await testSource({}).getPlaylistList(), isEmpty);
    });
  });

  group('lyric 歌词获取', () {
    test('text 响应直读并解析 LRC 时间戳', () async {
      final source = testSource({
        'lyric': {'url': '/lyric_text?id={id}', 'responseType': 'text'},
      });
      final lyrics = await source.getLyrics('s1');

      expect(lyrics, isNotNull);
      expect(lyrics!.songId, 's1');
      expect(lyrics.sourceId, 'rex');
      expect(lyrics.isLrc, isTrue);
      expect(lyrics.lines.length, 2);
      expect(lyrics.lines[0].text, '第一句');
      expect(lyrics.lines[0].time, const Duration(seconds: 12));
      expect(lyrics.lines[1].text, '第二句');
      expect(lyrics.lines[1].time, const Duration(milliseconds: 16500));
    });

    test('无时间戳纯文本退化为单行零时间，isLrc=false', () async {
      final source = testSource({
        'lyric': {'url': '/lyric_plain?id={id}', 'responseType': 'text'},
      });
      final lyrics = await source.getLyrics('s1');

      expect(lyrics, isNotNull);
      expect(lyrics!.isLrc, isFalse);
      expect(lyrics.lines.length, 1);
      expect(lyrics.lines.single.text, '纯文本歌词无时间戳');
      expect(lyrics.lines.single.time, Duration.zero);
    });

    test('JSON 响应用 contentRule 提取歌词文本', () async {
      final source = testSource({
        'lyric': {
          'url': '/lyric_json?id={id}',
          'responseType': 'json',
          'contentRule': r'$.lrc',
        },
      });
      final lyrics = await source.getLyrics('s1');

      expect(lyrics, isNotNull);
      expect(lyrics!.lines.length, 1);
      expect(lyrics.lines.single.text, 'JSON歌词');
      expect(lyrics.lines.single.time, const Duration(seconds: 1));
    });

    test('未配置 lyric 规则时返回 null', () async {
      expect(await testSource({}).getLyrics('s1'), isNull);
    });
  });

  group('搜索字段映射（_fieldsToSong）', () {
    /// 完整 itemRules 的搜索源（含未知字段 vip）
    RuleBasedMusicSource searchSource() => testSource({
          'search': {
            'url': '/search?keyword={keyword}&page={page}',
            'responseType': 'json',
            'listRule': r'$',
            'itemRules': {
              'id': 'id',
              'title': 'name',
              'artist': 'artist',
              'duration': 'duration',
              'playUrl': 'url',
              'vip': 'vip',
            },
          },
        });

    test('缺 id 或缺 title 的条目被跳过', () async {
      final result = await searchSource().search(keyword: 'fields');

      // 3 条数据中只有 1 条同时具备 id 和 title
      expect(result.songs.length, 1);
      expect(result.songs.single.title, '字段歌');
      expect(result.songs.single.artist, '歌手');
      expect(result.sourceId, 'rex');
    });

    test('duration 字符串解析为 int', () async {
      final result = await searchSource().search(keyword: 'fields');
      expect(result.songs.single.duration, 240);
    });

    test('playUrl 从 url 字段映射', () async {
      final result = await searchSource().search(keyword: 'fields');
      expect(result.songs.single.playUrl, 'http://play/1.mp3');
    });

    test('未知字段进 extra，已知字段不重复进 extra', () async {
      final result = await searchSource().search(keyword: 'fields');
      final extra = result.songs.single.extra;

      expect(extra['vip'], isTrue, reason: 'itemRules 提取的未知键应进 extra');
      // 已知键（映射到 Song 字段的 + quality 排除名单）不应重复进 extra
      expect(extra.containsKey('id'), isFalse);
      expect(extra.containsKey('title'), isFalse);
      expect(extra.containsKey('playUrl'), isFalse);
      expect(extra.containsKey('duration'), isFalse);
      expect(extra.containsKey('quality'), isFalse);
    });

    test("itemRules 用 'url' 键时同样兼容为 playUrl", () async {
      // 边界：规则里字段名就叫 url（而非 playUrl），_fieldsToSong 应兜底
      final source = testSource({
        'search': {
          'url': '/search2?keyword={keyword}',
          'responseType': 'json',
          'listRule': r'$',
          'itemRules': {'id': 'id', 'title': 'name', 'url': 'url'},
        },
      });
      final result = await source.search(keyword: 'any');

      expect(result.songs.single.playUrl, 'http://u/2.mp3');
    });
  });

  group('分页提取', () {
    test('size 类型：条数达到 limitValue → hasMore + nextPage', () async {
      final source = testSource({
        'search': {
          'url': '/search?keyword={keyword}&page={page}',
          'responseType': 'json',
          'listRule': r'$',
          'itemRules': {'id': 'id', 'title': 'name'},
          'pagination': {'type': 'size', 'limitValue': 2},
        },
      });
      final result = await source.search(keyword: 'two', page: 1);

      expect(result.songs.length, 2);
      expect(result.hasMore, isTrue);
      expect(result.nextPage, 2);
    });

    test('size 类型：条数不足 → 无更多', () async {
      final source = testSource({
        'search': {
          'url': '/search?keyword={keyword}&page={page}',
          'responseType': 'json',
          'listRule': r'$',
          'itemRules': {'id': 'id', 'title': 'name'},
          'pagination': {'type': 'size', 'limitValue': 2},
        },
      });
      final result = await source.search(keyword: 'one', page: 1);

      expect(result.songs.length, 1);
      expect(result.hasMore, isFalse);
      expect(result.nextPage, isNull);
    });

    test('cursor 类型：提取 nextCursor → hasMore', () async {
      final source = testSource({
        'search': {
          'url': '/search_cursor?keyword={keyword}',
          'responseType': 'json',
          'listRule': r'$.data',
          'itemRules': {'id': 'id', 'title': 'name'},
          'pagination': {'type': 'cursor', 'cursorRule': r'$.nextCursor'},
        },
      });
      final result = await source.search(keyword: 'any');

      expect(result.songs.length, 1);
      expect(result.hasMore, isTrue);
      expect(result.nextCursor, 'abc');
    });

    test('未配置 pagination → hasMore=false', () async {
      final source = testSource({
        'search': {
          'url': '/search?keyword={keyword}',
          'responseType': 'json',
          'listRule': r'$',
          'itemRules': {'id': 'id', 'title': 'name'},
        },
      });
      final result = await source.search(keyword: 'two');

      expect(result.hasMore, isFalse);
      expect(result.nextPage, isNull);
      expect(result.nextCursor, isNull);
      expect(result.nextOffset, isNull);
    });
  });

  group('HTTP 错误容错', () {
    test('搜索遇 500 → 返回空结果不抛异常', () async {
      final source = testSource({
        'search': {
          'url': '/search?keyword={keyword}',
          'responseType': 'json',
          'listRule': r'$',
          'itemRules': {'id': 'id', 'title': 'name'},
        },
      });
      final result = await source.search(keyword: 'boom');

      expect(result.songs, isEmpty);
      expect(result.sourceId, 'rex');
    });

    test('歌单详情遇 404 → getPlaylist 返回 null', () async {
      final source = testSource({
        'playlist': {
          'url': '/not_exist',
          'responseType': 'json',
          'listRule': r'$.tracks',
          'itemRules': {'id': 'id', 'title': 'name'},
        },
      });
      expect(await source.getPlaylist('x'), isNull);
      expect(await source.getPlaylistSongs('x'), isEmpty);
    });

    test('无 search 规则 → 空结果（不发请求）', () async {
      final result = await testSource({}).search(keyword: 'any');
      expect(result.songs, isEmpty);
      expect(result.sourceId, 'rex');
    });
  });
}
