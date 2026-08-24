import 'dart:convert';
import 'dart:io';

import 'package:crawler/crawler.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

/// 标记是否在 Flutter 环境中运行（JS 运行时需要 Flutter）
bool get _hasFlutter => false;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('crawler_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('HttpClient.resolveUrl', () {
    test('replaces single placeholder', () {
      final result = HttpClient.resolveUrl('/search?keyword={keyword}', {'keyword': 'hello'});
      expect(result, '/search?keyword=hello');
    });

    test('replaces multiple placeholders', () {
      final result = HttpClient.resolveUrl(
        '/search?keyword={keyword}&page={page}',
        {'keyword': 'test', 'page': '2'},
      );
      expect(result, '/search?keyword=test&page=2');
    });

    test('handles empty placeholders', () {
      final result = HttpClient.resolveUrl('/static/url', {});
      expect(result, '/static/url');
    });
  });

  group('RuleLoader', () {
    test('loads from JSON with all fields', () {
      final json = r'''{
        "source": {"id": "demo", "name": "Demo", "baseUrl": "https://api.example.com"},
        "search": {
          "url": "/search?keyword={keyword}&page={page}",
          "method": "GET",
          "responseType": "json",
          "listRule": "$.data.songs",
          "itemRules": {"id": "id", "title": "name", "artist": "artist.name"}
        }
      }''';
      final config = RuleLoader.loadFromJson(json);
      expect(config, isNotNull);
      expect(config!.source.id, 'demo');
      expect(config.search, isNotNull);
      expect(config.search!.itemRules['title'], 'name');
    });

    test('returns null for invalid JSON', () {
      final config = RuleLoader.loadFromJson('invalid');
      expect(config, isNull);
    });
  });

  group('RuleConfig fromJson', () {
    test('parses search rule', () {
      final json = {
        'url': '/search?q={keyword}',
        'method': 'GET',
        'responseType': 'json',
        'listRule': r'$.data',
        'itemRules': {'id': 'id', 'title': 'title'},
      };
      final rule = FlowRule.fromJson(json);
      expect(rule.url, '/search?q={keyword}');
      expect(rule.itemRules['id'], 'id');
    });

    test('parses pagination rule', () {
      final json = {
        'type': 'cursor',
        'cursorParam': 'cursor',
        'cursorRule': r'$.data.nextCursor',
      };
      final pagination = PaginationRule.fromJson(json);
      expect(pagination.type, 'cursor');
      expect(pagination.cursorRule, r'$.data.nextCursor');
    });
  });

  group('ResponseHandler', () {
    test('extractItem extracts fields from Map', () {
      final item = {'id': '1', 'name': 'Song', 'artist': {'name': 'Singer'}};
      final rules = {'id': r'$.id', 'title': r'$.name', 'artist': r'$.artist.name'};
      final fields = ResponseHandler.extractItem(item, rules);
      expect(fields['id'], '1');
      expect(fields['title'], 'Song');
      expect(fields['artist'], 'Singer');
    });

    test('extractList from JSON array', () {
      final data = {'songs': [{'id': '1'}, {'id': '2'}]};
      final items = ResponseHandler.extractList(data, r'$.songs');
      expect(items.length, 2);
    });

    test('extractList returns empty for no match', () {
      final items = ResponseHandler.extractList({'data': []}, r'$.nonexistent');
      expect(items, isEmpty);
    });
  });

  group('RuleBasedMusicSource', () {
    test('creates source info from rule config', () {
      final config = RuleConfig.fromJson({
        'source': {'id': 'test', 'name': 'Test Source', 'icon': 'https://example.com/icon.png'},
      });
      final source = RuleBasedMusicSource(config);
      expect(source.sourceInfo.id, 'test');
      expect(source.sourceInfo.name, 'Test Source');
      expect(source.sourceInfo.type, SourceType.rule);
    });

    test('search returns empty when no search rule', () async {
      final config = RuleConfig.fromJson({
        'source': {'id': 'no-search', 'name': 'No Search'},
      });
      final source = RuleBasedMusicSource(config);
      final result = await source.search(keyword: 'test');
      expect(result.songs, isEmpty);
    });
  });

  group('MusicFreeAdapter', () {
    test('converts single plugin JSON to source', () {
      final json = r'''{
        "name": "Demo Plugin",
        "url": "https://api.demo.com",
        "search": {
          "url": "/search?keyword={keyword}",
          "listRule": "$.data",
          "titleRule": "title",
          "artistRule": "artist"
        }
      }''';
      final source = MusicFreeAdapter.convertToSource(json);
      expect(source, isNotNull);
      expect(source!.sourceInfo.name, 'Demo Plugin');
    });

    test('converts plugin list JSON', () {
      final json = '''[{
        "name": "Plugin 1",
        "url": "https://api1.com"
      }, {
        "name": "Plugin 2",
        "url": "https://api2.com"
      }]''';
      final source = MusicFreeAdapter.convertToSource(json);
      expect(source, isNotNull);
      expect(source!.sourceInfo.name, 'Plugin 1');
    });

    test('returns null for invalid JSON', () {
      expect(MusicFreeAdapter.convertToSource('invalid'), isNull);
    });
  });

  group('LxMusicAdapter', () {
    test('returns null for empty content', () async {
      final source = await LxMusicAdapter.tryCreate('');
      expect(source, isNull);
    });

    test('extracts name from JS source', () async {
      final source = await LxMusicAdapter.tryCreate('const name = "Netease";');
      expect(source, isNotNull);
      expect(source!.sourceInfo.name, contains('Netease'));
    });

    test('extracts platform name from JS', () async {
      final source = await LxMusicAdapter.tryCreate('platform: "小秋音乐"');
      expect(source, isNotNull);
      expect(source!.sourceInfo.name, contains('小秋音乐'));
    });
  });

  group('PluginManager - real files', () {
    test('loadPlugin loads .json file', () async {
      final file = File('${tempDir.path}/test_plugin.json');
      file.writeAsStringSync(r'''{
        "name": "File Plugin",
        "url": "https://api.test.com",
        "search": {
          "url": "/search?keyword={keyword}",
          "listRule": "$.data",
          "titleRule": "title"
        }
      }''');
      final source = await PluginManager.loadPlugin(file.path);
      expect(source, isNotNull);
      expect(source!.sourceInfo.name, 'File Plugin');
    });

    test('loadPlugin returns null for unknown extension', () async {
      final file = File('${tempDir.path}/test.txt');
      file.writeAsStringSync('some data');
      expect(await PluginManager.loadPlugin(file.path), isNull);
    });

    test('loadPluginsFromDirectory loads all JSON plugins', () async {
      File('${tempDir.path}/a.json').writeAsStringSync(r'''{
        "name": "Plugin A", "url": "https://a.com"
      }''');
      File('${tempDir.path}/b.json').writeAsStringSync(r'''{
        "name": "Plugin B", "url": "https://b.com"
      }''');
      File('${tempDir.path}/ignore.txt').writeAsStringSync('not a plugin');

      final sources = await PluginManager.loadPluginsFromDirectory(tempDir.path);
      expect(sources.length, 2);
      expect(sources.any((s) => s.sourceInfo.name == 'Plugin A'), isTrue);
      expect(sources.any((s) => s.sourceInfo.name == 'Plugin B'), isTrue);
    });

    test('loadPluginsFromDirectory returns empty for missing dir', () async {
      final sources = await PluginManager.loadPluginsFromDirectory('/nonexistent/path');
      expect(sources, isEmpty);
    });
  });

  group('RuleLoader - real files', () {
    test('loadFromFile loads from file path', () {
      final file = File('${tempDir.path}/rule.json');
      file.writeAsStringSync(r'''{
        "source": {"id": "file_rule", "name": "File Rule"},
        "search": {
          "url": "/search?q={keyword}",
          "responseType": "json",
          "listRule": "$.data",
          "itemRules": {"id": "id", "title": "title"}
        }
      }''');
      final config = RuleLoader.loadFromFile(file.path);
      expect(config, isNotNull);
      expect(config!.source.id, 'file_rule');
    });

    test('loadAllFromDirectory loads all rules', () {
      File('${tempDir.path}/r1.json').writeAsStringSync(r'''{
        "source": {"id": "r1", "name": "Rule 1"}
      }''');
      File('${tempDir.path}/r2.json').writeAsStringSync(r'''{
        "source": {"id": "r2", "name": "Rule 2"}
      }''');
      final configs = RuleLoader.loadAllFromDirectory(tempDir.path);
      expect(configs.length, 2);
    });
  });

  group('Full flow: search → detail → play URL', () {
    late HttpServer server;
    late int port;
    late RuleBasedMusicSource source;

    setUp(() async {
      server = await HttpServer.bind('localhost', 0);
      port = server.port;

      server.listen((request) {
        final uri = request.uri;
        final keyword = uri.queryParameters['keyword'] ?? '';
        final id = uri.queryParameters['id'] ?? '';

        if (uri.path == '/search' && keyword == 'test') {
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({
              'data': {
                'songs': [
                  {
                    'id': 'song_001',
                    'name': 'Test Song',
                    'artist': {'name': 'Test Artist'},
                    'cover_url': 'https://example.com/cover.jpg',
                    'duration_seconds': 240,
                    'url': 'http://localhost:$port/play/song_001.mp3',
                    'lyric_url': 'http://localhost:$port/lyric/song_001.lrc',
                  },
                ],
              },
            }))
            ..close();
        } else if (uri.path == '/song' && id == 'song_001') {
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({
              'data': {
                'play_url': 'http://localhost:$port/play/song_001.mp3',
                'cover_large': 'https://example.com/cover_large.jpg',
                'lyric_url': 'http://localhost:$port/lyric/song_001.lrc',
              },
            }))
            ..close();
        } else {
          request.response..statusCode = 404..write('{}')..close();
        }
      });

      final config = RuleConfig.fromJson({
        'source': {'id': 'test_source', 'name': 'Test Source', 'baseUrl': 'http://localhost:$port'},
        'search': {
          'url': '/search?keyword={keyword}&page={page}',
          'method': 'GET',
          'responseType': 'json',
          'listRule': r'$.data.songs',
          'itemRules': {
            'id': 'id',
            'title': 'name',
            'artist': 'artist.name',
            'cover': 'cover_url',
            'duration': 'duration_seconds',
            'playUrl': 'url',
            'lyricUrl': 'lyric_url',
          },
        },
        'songDetail': {
          'url': '/song?id={id}',
          'method': 'GET',
          'responseType': 'json',
          'listRule': r'$.data',
          'itemRules': {
            'playUrl': 'play_url',
            'cover': 'cover_large',
            'lyricUrl': 'lyric_url',
          },
        },
      });
      source = RuleBasedMusicSource(config);
    });

    tearDown(() async {
      await server.close();
    });

    test('search returns parsed songs', () async {
      final result = await source.search(keyword: 'test');
      expect(result.songs.length, 1);
      expect(result.songs.first.title, 'Test Song');
      expect(result.songs.first.artist, 'Test Artist');
      expect(result.songs.first.playUrl, 'http://localhost:$port/play/song_001.mp3');
    });

    test('getSongUrl returns play URL', () async {
      final url = await source.getSongUrl('song_001');
      expect(url, 'http://localhost:$port/play/song_001.mp3');
    });
  });

  group('真实插件下载', () {
    test('从默认源下载插件列表并解析', () async {
      final downloader = PluginDownloader();
      final savePath = '${tempDir.path}/plugin_list.json';

      final path = await downloader.downloadPlugin(
        'https://fastly.jsdelivr.net/gh/Huibq/keep-alive/Music_Free/myPlugins.json',
        savePath,
      );
      expect(path, isNotNull);

      final content = File(path!).readAsStringSync();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final plugins = json['plugins'] as List;
      expect(plugins.length, greaterThan(0));
      expect(plugins.any((p) => (p as Map)['name'] == '小秋音乐'), isTrue);
      downloader.dispose();
    });

    test('下载所有 5 个插件并验证结构', () async {
      final downloader = PluginDownloader();
      final listPath = '${tempDir.path}/plugin_list.json';

      // 下载插件列表
      await downloader.downloadPlugin(
        'https://fastly.jsdelivr.net/gh/Huibq/keep-alive/Music_Free/myPlugins.json',
        listPath,
      );
      final listContent = File(listPath).readAsStringSync();
      final listJson = jsonDecode(listContent) as Map<String, dynamic>;
      final plugins = (listJson['plugins'] as List).cast<Map<String, dynamic>>();

      // 下载每个插件并验证
      for (final plugin in plugins) {
        final name = plugin['name'] as String;
        final url = plugin['url'] as String;
        final version = plugin['version'] as String?;

        final savePath = '${tempDir.path}/${name}.js';
        final path = await downloader.downloadPlugin(url, savePath);
        expect(path, isNotNull, reason: '下载失败: $name');

        final content = File(path!).readAsStringSync();
        expect(content.isNotEmpty, isTrue, reason: '插件内容为空: $name');
        expect(content.length, greaterThan(100), reason: '插件文件过小: $name ($version)');
        expect(content, contains('search'), reason: '插件缺少 search 函数: $name');
        expect(content, contains('platform'), reason: '插件缺少 platform 字段: $name');

        // 检查是否包含 getMediaSource 或 getSongUrl 函数
        final hasMediaSource = content.contains('getMediaSource') || content.contains('getSongUrl');
        expect(hasMediaSource, isTrue, reason: '插件缺少播放 URL 函数: $name');
      }
      downloader.dispose();
    });
  });

  group('JS 插件运行时测试', () {
    /// 单元测试中无法运行 JS（需要 Flutter 平台环境）
    const _canRunJs = false;

    test('下载并加载插件到 JsRuntime', () async {
      final downloader = PluginDownloader();

      // 下载小秋音乐插件
      final jsPath = '${tempDir.path}/xiaoqiu.js';
      await downloader.downloadPlugin(
        'https://fastly.jsdelivr.net/gh/Huibq/keep-alive/Music_Free/xiaoqiu.js',
        jsPath,
      );
      downloader.dispose();

      final jsContent = File(jsPath).readAsStringSync();

      if (!_canRunJs) {
        // 无法运行 JS，验证插件可被 LxMusicAdapter 正确识别
        final source = await LxMusicAdapter.tryCreate(jsContent);
        expect(source, isNotNull);
        expect(source!.sourceInfo.name, contains('小秋音乐'));
        return;
      }

      // 初始化 JS 运行时并加载插件
      final runtime = JsRuntime();
      await runtime.init();
      await runtime.loadPlugin(jsContent);

      final loaded = await runtime.isPluginLoaded();
      expect(loaded, isTrue, reason: '插件加载失败');

      // 检查插件导出的函数
      expect(await runtime.hasFunction('search'), isTrue, reason: 'search 函数未导出');
      expect(await runtime.hasFunction('getMediaSource'), isTrue, reason: 'getMediaSource 函数未导出');

      // 执行搜索
      final searchResult = await runtime.callPluginFunction("search('周杰伦', 1, 'music')");
      expect(searchResult, isNotNull);
      expect(searchResult, isNot(contains('"error"')), reason: '搜索出错: $searchResult');

      // 解析搜索结果
      final searchJson = jsonDecode(searchResult!) as Map<String, dynamic>;
      final data = searchJson['data'] as List?;
      expect(data, isNotEmpty, reason: '搜索无结果');

      // 获取第一首歌的播放 URL
      if (data!.isNotEmpty) {
        final firstSong = data.first as Map<String, dynamic>;
        final songId = firstSong['id']?.toString() ?? firstSong['songmid']?.toString() ?? '';
        expect(songId.isNotEmpty, isTrue, reason: '歌曲 ID 为空');

        // 获取播放 URL
        final urlResult = await runtime.callPluginFunction(
          "(async function() { const item = (await window.__plugin.search('周杰伦', 1, 'music')).data[0]; const media = await window.__plugin.getMediaSource(item, 'standard'); return JSON.stringify(media); })()",
        );
        expect(urlResult, isNotNull);
        expect(urlResult, isNot(contains('"error"')), reason: '获取播放 URL 出错: $urlResult');

        final urlJson = jsonDecode(urlResult!) as Map<String, dynamic>;
        final playUrl = urlJson['url'] as String?;
        expect(playUrl, isNotEmpty, reason: '播放 URL 为空');
      }

      await runtime.dispose();
    });
  });
}