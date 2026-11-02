/// 人机验证流程测试（本地 HTTP 桩 + 真实引擎，不依赖外网）
///
/// 场景（与歌曲宝一致）：换播放地址那步回 {"code":2,"msg":"请完成人机验证后继续"}，
/// 只有带上验证码（captchaCode + 挑战里的 key）重试，源站才回真实地址。
///
/// 覆盖两条：
///   ① 首次 getPlayable 返回 challenge（含验证图与 key），而不是含糊的"空地址"；
///   ② 带验证码重试后拿到真实播放地址。
///
/// 模拟数据：本地 HttpServer 按规则声明返回详情页/换址接口/验证图接口。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crawler/crawler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late int port;

  /// 正确的验证码（桩只认这一个，用来验证"回传字段确实生效"）
  const rightCode = 'AB12';

  /// 收到的换址请求体（断言字段名与内容）
  final bodies = <String>[];

  setUp(() async {
    bodies.clear();
    server = await HttpServer.bind('localhost', 0);
    port = server.port;
    server.listen((request) async {
      final res = request.response;
      final path = request.uri.path;
      if (path == '/detail/1') {
        res
          ..headers.contentType = ContentType.html
          ..write('<html><body>'
              '<h1 class="song-title-styled"><span>默</span></h1>'
              '<script>var play_id="' + 'P' * 120 + '";</script>'
              '</body></html>');
      } else if (path == '/captcha') {
        res
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'code': 1,
            'data': {'key': 'KEY-1', 'img': 'data:image/png;base64,AAAA'},
          }));
      } else if (path == '/play-url') {
        final body = await utf8.decoder.bind(request).join();
        bodies.add(body);
        final ok = body.contains('captchaCode=' + rightCode) && body.contains('key=KEY-1');
        res
          ..headers.contentType = ContentType.json
          ..write(ok
              ? jsonEncode({'code': 1, 'data': {'url': 'http://localhost:' + port.toString() + '/a.mp3'}})
              : jsonEncode({'code': 2, 'msg': '请完成人机验证后继续'}));
      } else {
        res.statusCode = HttpStatus.notFound;
      }
      await res.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  /// 规则：详情页拿 play_id → 换址接口；captcha 块声明验证流程
  RuleConfig config() => RuleConfig.fromJson({
        'source': {'id': 'stub', 'name': '桩源', 'baseUrl': 'http://localhost:' + port.toString()},
        'songDetail': {
          'captcha': {
            'endpoint': '/captcha',
            'imagePath': r'$.data.img',
            'keyPath': r'$.data.key',
            'messagePath': r'$.msg',
            'codeField': 'captchaCode',
            'keyField': 'key',
            'challengeCode': 2,
          },
          'steps': [
            {
              'url': '/detail/{id}',
              'method': 'GET',
              'responseType': 'html',
              'extract': {'playId': r'@Regex:play_id="([^"]+)"'},
            },
            {
              'url': '/play-url',
              'method': 'POST',
              'responseType': 'json',
              'body': 'id={playId}&purpose=play',
              'listRule': r'$',
              'itemRules': {'playUrl': r'$.data.url'},
            },
          ],
        },
      });

  group('源站人机验证', () {
    test('首次取址：如实返回挑战（含验证图与 key），而不是空地址', () async {
      final source = RuleBasedMusicSource(config());
      await source.init();

      final info = await source.getPlayable('1');

      expect(info.url, isEmpty);
      expect(info.hasUrl, isFalse);
      expect(info.needsChallenge, isTrue);
      expect(info.challenge!.image, 'data:image/png;base64,AAAA');
      expect(info.challenge!.key, 'KEY-1');
      expect(info.challenge!.message, contains('人机验证'));
      expect(bodies.single, isNot(contains('captchaCode=')), reason: '首次不带验证码');
    });

    test('带验证码重试：字段名与内容按配置回传，拿到真实地址', () async {
      final source = RuleBasedMusicSource(config());
      await source.init();

      final info = await source.getPlayable('1',
          captchaCode: rightCode, captchaKey: 'KEY-1');

      expect(info.needsChallenge, isFalse);
      expect(info.url, endsWith('/a.mp3'));
      expect(bodies.last, contains('captchaCode=' + rightCode));
      expect(bodies.last, contains('key=KEY-1'));
      expect(bodies.last, startsWith('id='), reason: '原有字段必须保留');
    });

    test('验证码错误：仍然如实返回新的挑战（不假装成功）', () async {
      final source = RuleBasedMusicSource(config());
      await source.init();

      final info = await source.getPlayable('1', captchaCode: 'WRONG');

      expect(info.url, isEmpty);
      expect(info.needsChallenge, isTrue);
      expect(info.challenge!.key, 'KEY-1', reason: '要能再次弹图重试');
    });
  });
}
