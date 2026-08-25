import 'dart:convert';
import 'dart:io';

import 'package:crawler/crawler.dart';
import 'package:core/core.dart';
import 'package:expr/expr.dart';
import 'package:test/test.dart';

/// 测试前置流程（preflight）功能：
/// - 人机验证 / CSRF token 提取
/// - 步骤间变量传递
/// - 缓存行为
/// - 实例间 cookie 隔离
void main() {
  group('PreflightRule JSON parsing', () {
    test('parses single-step preflight', () {
      final json = {
        'steps': [
          {
            'method': 'GET',
            'url': '/',
            'responseType': 'html',
            'extract': {'csrf_token': r"@CSS:input[name='csrf_token']@value"},
          },
          {
            'method': 'POST',
            'url': '/',
            'body': 'csrf_token={csrf_token}&human_check=on',
            'contentType': 'application/x-www-form-urlencoded',
          },
        ],
        'cacheMinutes': 50,
      };
      final rule = PreflightRule.fromJson(json);
      expect(rule.steps.length, 2);
      expect(rule.steps[0].method, 'GET');
      expect(rule.steps[0].extract!['csrf_token'],
          r"@CSS:input[name='csrf_token']@value");
      expect(rule.steps[1].body, 'csrf_token={csrf_token}&human_check=on');
      expect(rule.cacheMinutes, 50);
    });

    test('parses preflight with no cache (null cacheMinutes)', () {
      final json = {
        'steps': [
          {
            'method': 'GET',
            'url': '/init',
            'responseType': 'json',
            'extract': {'token': r'$.token'},
          },
        ],
      };
      final rule = PreflightRule.fromJson(json);
      expect(rule.steps.length, 1);
      expect(rule.cacheMinutes, isNull);
    });

    test('parses RuleConfig with preflight', () {
      final json = {
        'source': {'id': 'test', 'name': 'Test'},
        'preflight': {
          'steps': [
            {'method': 'GET', 'url': '/auth', 'responseType': 'json'},
          ],
          'cacheMinutes': 30,
        },
        'search': {
          'url': '/search?keyword={keyword}',
          'responseType': 'json',
          'listRule': r'$.data',
          'itemRules': {'id': 'id', 'title': 'title'},
        },
      };
      final config = RuleConfig.fromJson(json);
      expect(config.preflight, isNotNull);
      expect(config.preflight!.steps.length, 1);
      expect(config.preflight!.cacheMinutes, 30);
      expect(config.search, isNotNull);
    });
  });

  group('Preflight flow - real HTTP server', () {
    /// 模拟 6uq.cn 的人机验证流程：
    /// 1. GET / → 返回含 csrf_token 的 HTML
    /// 2. POST / 带 csrf_token + human_check → 设置 cookie
    /// 3. 后续请求通过 cookie 验证
    late HttpServer server;
    late int port;
    int step1Count = 0;
    int step2Count = 0;
    String? capturedCookie;

    /// 模拟搜索请求的追踪
    int searchCount = 0;

    setUp(() async {
      step1Count = 0;
      step2Count = 0;
      searchCount = 0;
      capturedCookie = null;

      server = await HttpServer.bind('localhost', 0);
      port = server.port;

      server.listen((request) async {
        final uri = request.uri;

        try {
          // Step 1: GET / → 返回含 csrf_token 的 HTML
          if (uri.path == '/' && request.method == 'GET') {
            step1Count++;
            request.response
              ..statusCode = 200
              ..headers.contentType = ContentType.html
              ..write('''
<html>
<body>
  <form>
    <input name="csrf_token" value="test_token_abc123">
    <input type="checkbox" name="human_check">
  </form>
</body>
</html>''')
              ..close();
            return;
          }

          // Step 2: POST / → 验证 csrf_token + human_check → 设置 cookie
          if (uri.path == '/' && request.method == 'POST') {
            step2Count++;
            final body = await utf8.decodeStream(request);
            final params = Uri.splitQueryString(body);
            final csrf = params['csrf_token'];
            final human = params['human_check'];

            if (csrf == 'test_token_abc123' && human == 'on') {
              request.response
                ..statusCode = 200
                ..headers.add('set-cookie', 'session=valid_session_123; Path=/')
                ..write('OK')
                ..close();
            } else {
              request.response
                ..statusCode = 403
                ..write('Invalid')
                ..close();
            }
            return;
          }

          // 搜索请求：需要 cookie 验证
          if (uri.path == '/search') {
            searchCount++;
            final cookie = request.headers.value('cookie') ?? '';
            if (cookie.contains('session=valid_session_123')) {
              capturedCookie = cookie;
              request.response
                ..statusCode = 200
                ..headers.contentType = ContentType.json
                ..write(jsonEncode({
                  'data': {
                    'songs': [
                      {
                        'id': 'song_001',
                        'name': 'Test Song',
                        'artist': 'Test Artist',
                      },
                    ],
                  },
                }))
                ..close();
            } else {
              request.response
                ..statusCode = 403
                ..write('Unauthorized')
                ..close();
            }
            return;
          }

          request.response..statusCode = 404..close();
        } catch (e) {
          request.response
            ..statusCode = 500
            ..write('Server error: $e')
            ..close();
        }
      });
    });

    tearDown(() async {
      await server.close();
    });

    test('preflight 执行 CSRF 验证流程后再搜索', () async {
      final config = RuleConfig.fromJson({
        'source': {
          'id': 'csrf_test',
          'name': 'CSRF Test',
          'baseUrl': 'http://localhost:$port',
        },
        'preflight': {
          'steps': [
            {
              'method': 'GET',
              'url': '/',
              'responseType': 'html',
              'extract': {
                'csrf_token': r"@CSS:input[name='csrf_token']@value",
              },
            },
            {
              'method': 'POST',
              'url': '/',
              'body': 'csrf_token={csrf_token}&human_check=on',
              'contentType': 'application/x-www-form-urlencoded',
            },
          ],
          'cacheMinutes': 50,
        },
        'search': {
          'url': '/search?keyword={keyword}',
          'method': 'GET',
          'responseType': 'json',
          'listRule': r'$.data.songs',
          'itemRules': {
            'id': 'id',
            'title': 'name',
            'artist': 'artist',
          },
        },
      });

      final source = RuleBasedMusicSource(config);
      final result = await source.search(keyword: 'test');

      expect(step1Count, 1, reason: 'Step 1 (GET /) 应执行一次');
      expect(step2Count, 1, reason: 'Step 2 (POST /) 应执行一次');
      expect(result.songs.length, 1);
      expect(result.songs.first.title, 'Test Song');
    });

    test('preflight 缓存：第二次搜索不重复执行前置步骤', () async {
      final config = RuleConfig.fromJson({
        'source': {
          'id': 'cache_test',
          'name': 'Cache Test',
          'baseUrl': 'http://localhost:$port',
        },
        'preflight': {
          'steps': [
            {
              'method': 'GET',
              'url': '/',
              'responseType': 'html',
              'extract': {
                'csrf_token': r"@CSS:input[name='csrf_token']@value",
              },
            },
            {
              'method': 'POST',
              'url': '/',
              'body': 'csrf_token={csrf_token}&human_check=on',
              'contentType': 'application/x-www-form-urlencoded',
            },
          ],
          'cacheMinutes': 50,
        },
        'search': {
          'url': '/search?keyword={keyword}',
          'method': 'GET',
          'responseType': 'json',
          'listRule': r'$.data.songs',
          'itemRules': {
            'id': 'id',
            'title': 'name',
            'artist': 'artist',
          },
        },
      });

      final source = RuleBasedMusicSource(config);
      await source.search(keyword: 'first');
      await source.search(keyword: 'second');

      // 前置步骤应只执行一次（缓存生效）
      expect(step1Count, 1, reason: '缓存应阻止重复执行 Step 1');
      expect(step2Count, 1, reason: '缓存应阻止重复执行 Step 2');
      expect(searchCount, 2, reason: '真实搜索请求应执行两次（不同关键词）');
    });

    test('preflight 空时不执行', () async {
      final config = RuleConfig.fromJson({
        'source': {
          'id': 'no_preflight',
          'name': 'No Preflight',
          'baseUrl': 'http://localhost:$port',
        },
        'search': {
          'url': '/search?keyword={keyword}',
          'method': 'GET',
          'responseType': 'json',
          'listRule': r'$.data.songs',
          'itemRules': {
            'id': 'id',
            'title': 'name',
            'artist': 'artist',
          },
        },
      });

      final source = RuleBasedMusicSource(config);
      // 无 preflight 配置，直接搜索（无 cookie 返回 403，被 try-catch 捕获返回空）
      final result = await source.search(keyword: 'test');
      expect(step1Count, 0, reason: '无 preflight 配置不应执行前置步骤');
      expect(result.songs, isEmpty, reason: '无 cookie 应返回空结果');
    });
  });

  group('Cookie 隔离', () {
    late HttpServer server;
    late int port;

    setUp(() async {
      server = await HttpServer.bind('localhost', 0);
      port = server.port;

      server.listen((request) {
        final uri = request.uri;

        // 两个不同的源，设置不同的 cookie
        if (uri.path == '/auth_a') {
          request.response
            ..statusCode = 200
            ..headers.add('set-cookie', 'source=a_only; Path=/')
            ..write('OK')
            ..close();
          return;
        }
        if (uri.path == '/auth_b') {
          request.response
            ..statusCode = 200
            ..headers.add('set-cookie', 'source=b_only; Path=/')
            ..write('OK')
            ..close();
          return;
        }

        // 检查 cookie 并返回
        if (uri.path == '/check') {
          final cookie = request.headers.value('cookie') ?? '';
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'cookie': cookie}))
            ..close();
          return;
        }

        request.response..statusCode = 404..close();
      });
    });

    tearDown(() async {
      await server.close();
    });

    test('两个 HttpClient 实例的 cookie 互不干扰', () async {
      final clientA = HttpClient(baseUrl: 'http://localhost:$port');
      final clientB = HttpClient(baseUrl: 'http://localhost:$port');

      // 源 A 获取认证 cookie
      await clientA.get('/auth_a');
      // 源 B 获取不同的认证 cookie
      await clientB.get('/auth_b');

      // 源 A 只应有 source=a_only
      final respA = await clientA.get('/check', responseType: 'json');
      final cookieA = respA.data['cookie'] as String? ?? '';
      expect(cookieA, contains('source=a_only'));
      expect(cookieA, isNot(contains('source=b_only')),
          reason: '源 A 不应看到源 B 的 cookie');

      // 源 B 只应有 source=b_only
      final respB = await clientB.get('/check', responseType: 'json');
      final cookieB = respB.data['cookie'] as String? ?? '';
      expect(cookieB, contains('source=b_only'));
      expect(cookieB, isNot(contains('source=a_only')),
          reason: '源 B 不应看到源 A 的 cookie');
    });

    test('独立的 RuleExecutor 实例 cookie 隔离', () async {
      // 源 A 配置：带 preflight 设置 cookie
      final configA = RuleConfig.fromJson({
        'source': {
          'id': 'source_a',
          'name': 'Source A',
          'baseUrl': 'http://localhost:$port',
        },
        'preflight': {
          'steps': [
            {
              'method': 'GET',
              'url': '/auth_a',
              'responseType': 'json',
            },
          ],
        },
        'search': {
          'url': '/check',
          'method': 'GET',
          'responseType': 'json',
          'listRule': r'$',
          'itemRules': {'id': 'cookie', 'title': 'cookie'},
        },
      });

      // 源 B 配置：带 preflight 设置不同 cookie
      final configB = RuleConfig.fromJson({
        'source': {
          'id': 'source_b',
          'name': 'Source B',
          'baseUrl': 'http://localhost:$port',
        },
        'preflight': {
          'steps': [
            {
              'method': 'GET',
              'url': '/auth_b',
              'responseType': 'json',
            },
          ],
        },
        'search': {
          'url': '/check',
          'method': 'GET',
          'responseType': 'json',
          'listRule': r'@Json:$',
          'itemRules': {'id': 'cookie', 'title': 'cookie'},
        },
      });

      final sourceA = RuleBasedMusicSource(configA);
      final sourceB = RuleBasedMusicSource(configB);

      // 各自执行搜索（触发各自的 preflight + search）
      final resultA = await sourceA.search(keyword: 'test');
      final resultB = await sourceB.search(keyword: 'test');

      // 源 A 只应有 source=a_only
      final cookieA = resultA.songs.firstOrNull?.id ?? '';
      expect(cookieA, contains('source=a_only'));
      expect(cookieA, isNot(contains('source=b_only')),
          reason: '源 A 的 cookie 不应包含源 B 的内容');

      // 源 B 只应有 source=b_only
      final cookieB = resultB.songs.firstOrNull?.id ?? '';
      expect(cookieB, contains('source=b_only'));
      expect(cookieB, isNot(contains('source=a_only')),
          reason: '源 B 的 cookie 不应包含源 A 的内容');
    });
  });
}