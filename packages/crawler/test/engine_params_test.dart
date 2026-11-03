// 详情/歌词流程的 params 拆分、可选步骤与译文合并（真实 HTTP 桩）
//
// 背景：GD音乐台这类源，搜索侧同时拿到 trackId 与 picId，而详情接口（types=url）
// 要 trackId、封面接口（types=pic）要 picId。规则用复合 ID（trackId~picId）
// 加上 params 表达式，在详情/歌词流程里把两个 ID 拆开。
//
// 这里用本地 HTTP 桩验证"拆开的参数确实进了请求"，并覆盖三条边界：
//   ① 可选步骤失败不毁掉播放地址；② 必需步骤失败照旧抛出（不假装有地址）；
//   ③ 译文缺失时歌词行为与"不配译文"完全一致。

import 'dart:convert';
import 'dart:io';

import 'package:crawler/crawler.dart';
import 'package:test/test.dart';

void main() {
  group('规则解析', () {
    test('lyric 节点解析 params/translationRule/translationJoin', () {
      final config = RuleConfig.fromJson({
        'source': {'id': 'x', 'name': 'X'},
        'lyric': {
          'url': '/l?id={id}',
          'responseType': 'json',
          'params': {'id': r'$.id && @Regex:^[^~]+'},
          'contentRule': r'$.lyric',
          'translationRule': r'$.tlyric',
          'translationJoin': ' | ',
        },
      });

      expect(config.lyric!.params!['id'], r'$.id && @Regex:^[^~]+');
      expect(config.lyric!.translationRule, r'$.tlyric');
      expect(config.lyric!.translationJoin, ' | ');
    });

    test('未写 optional 的步骤默认必需（false）', () {
      final config = RuleConfig.fromJson({
        'source': {'id': 'x', 'name': 'X'},
        'songDetail': {
          'steps': [
            {'url': '/a', 'responseType': 'json'},
            {'url': '/b', 'responseType': 'json', 'optional': true},
          ],
        },
      });

      expect(config.songDetail!.steps![0].optional, isFalse);
      expect(config.songDetail!.steps![1].optional, isTrue);
    });
  });

  group('详情/歌词流程 params 拆分（HTTP 桩）', () {
    late HttpServer server;
    late int port;

    /// 桩收到过的请求（path+query，按调用顺序）
    final requests = <String>[];

    setUp(() async {
      requests.clear();
      server = await HttpServer.bind('localhost', 0);
      port = server.port;

      server.listen((request) async {
        final uri = request.uri;
        requests.add(uri.toString());
        final id = uri.queryParameters['id'] ?? '';
        final res = request.response;

        void json(int status, Map<String, dynamic> body) {
          res.statusCode = status;
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode(body));
        }

        // 桩语义：id 为空、或还是复合 ID（含 ~）→ 400
        // （真实 GD 接口对脏 id 的回应就是 400 Field id is invalid/required）
        if (id.isEmpty || id.contains('~')) {
          json(400, {'detail': 'Field `id` is invalid.'});
        } else if (uri.path == '/pic') {
          if (id == 'cover-ok') {
            json(200, {'url': 'http://cdn.local/cover.jpg'});
          } else {
            json(404, {'detail': 'no cover'});
          }
        } else if (uri.path == '/url') {
          json(200, {'url': 'http://cdn.local/play.mp3', 'br': 320});
        } else if (uri.path == '/lyric') {
          json(200, {
            'lyric': id == 'no-trans'
                ? '[00:01.00]Hi'
                : '[00:01.00]Hi\n[00:02.00]Bye',
            'tlyric': id == 'no-trans'
                ? ''
                : '[00:01.00]你好\n[00:02.00]再见',
          });
        } else {
          res.statusCode = 404;
        }
        await res.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    /// 造一个指向本地桩的 RuleExecutor
    RuleExecutor executorFor(
      Map<String, dynamic> songDetail, {
      Map<String, dynamic>? lyric,
    }) {
      final config = RuleConfig.fromJson({
        'source': {
          'id': 'stub',
          'name': 'Stub',
          'baseUrl': 'http://localhost:$port',
        },
        'songDetail': songDetail,
        'lyric': ?lyric,
      });
      return RuleExecutor(config);
    }

    /// 复合 ID 的拆分规则：~ 前是 trackId，~ 后是 picId
    Map<String, String> splitParams() => {
          'id': r'$.id && @Regex:^[^~]+',
          'picId': r'$.id && @Regex:[^~]+$',
        };

    test('steps 详情：复合 ID 拆成 trackId/picId，字段合并封面与播放地址', () async {
      final executor = executorFor({
        'params': splitParams(),
        'steps': [
          {
            'url': '/pic?id={picId}',
            'responseType': 'json',
            'optional': true,
            'listRule': r'$',
            'itemRules': {'coverUrl': r'$.url'},
          },
          {
            'url': '/url?id={id}',
            'responseType': 'json',
            'listRule': r'$',
            'itemRules': {'playUrl': r'$.url', 'quality': r'$.br'},
          },
        ],
      });

      final fields = await executor.executeSongDetail('track-1~cover-ok');

      expect(fields['playUrl'], 'http://cdn.local/play.mp3');
      expect(fields['coverUrl'], 'http://cdn.local/cover.jpg');
      expect(fields['quality'], 320);
      // 关键断言：两个接口各自拿到拆开的参数，没把复合 ID 原样发出去
      expect(requests, ['/pic?id=cover-ok', '/url?id=track-1']);
    });

    test('可选步骤失败：封面 404 不影响播放地址', () async {
      final executor = executorFor({
        'params': splitParams(),
        'steps': [
          {
            'url': '/pic?id={picId}',
            'responseType': 'json',
            'optional': true,
            'listRule': r'$',
            'itemRules': {'coverUrl': r'$.url'},
          },
          {
            'url': '/url?id={id}',
            'responseType': 'json',
            'listRule': r'$',
            'itemRules': {'playUrl': r'$.url'},
          },
        ],
      });

      final fields = await executor.executeSongDetail('track-1~no-cover');

      expect(fields['playUrl'], 'http://cdn.local/play.mp3');
      expect(fields.containsKey('coverUrl'), isFalse, reason: '封面取不到就不该编造');
    });

    test('未标 optional 的步骤失败照旧抛出（不假装有地址）', () async {
      final executor = executorFor({
        'params': splitParams(),
        'steps': [
          {
            'url': '/pic?id={picId}',
            'responseType': 'json',
            'listRule': r'$',
            'itemRules': {'coverUrl': r'$.url'},
          },
          {
            'url': '/url?id={id}',
            'responseType': 'json',
            'listRule': r'$',
            'itemRules': {'playUrl': r'$.url'},
          },
        ],
      });

      await expectLater(
        executor.executeSongDetail('track-1~no-cover'),
        throwsA(isA<Exception>()),
      );
    });

    test('单请求详情：params 同样生效', () async {
      final executor = executorFor({
        'url': '/url?id={id}',
        'responseType': 'json',
        'params': splitParams(),
        'listRule': r'$',
        'itemRules': {'playUrl': r'$.url'},
      });

      final fields = await executor.executeSongDetail('track-1~cover-ok');

      expect(fields['playUrl'], 'http://cdn.local/play.mp3');
      expect(requests, ['/url?id=track-1']);
    });

    test('歌词：params 拆 ID，译文按时间戳并进同一行', () async {
      final executor = executorFor(
        {'url': '/url?id={id}', 'responseType': 'json'},
        lyric: {
          'url': '/lyric?id={id}',
          'responseType': 'json',
          'params': splitParams(),
          'contentRule': r'$.lyric',
          'translationRule': r'$.tlyric',
          'translationJoin': ' / ',
        },
      );

      final lyric = await executor.executeLyric('track-1~cover-ok');

      expect(requests, ['/lyric?id=track-1']);
      expect(lyric, '[00:01.00]Hi / 你好\n[00:02.00]Bye / 再见');
    });

    test('译文为空时与"不配译文"行为一致（原样返回原文）', () async {
      final executor = executorFor(
        {'url': '/url?id={id}', 'responseType': 'json'},
        lyric: {
          'url': '/lyric?id={id}',
          'responseType': 'json',
          'params': splitParams(),
          'contentRule': r'$.lyric',
          'translationRule': r'$.tlyric',
          'translationJoin': ' / ',
        },
      );

      final lyric = await executor.executeLyric('no-trans~cover-ok');

      expect(lyric, '[00:01.00]Hi');
    });
  });
}
