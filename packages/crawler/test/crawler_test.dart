import 'package:crawler/crawler.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
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
    test('creates stub source for valid JS', () {
      final source = LxMusicAdapter.tryCreate('const name = "MyPlugin";');
      expect(source, isNotNull);
      expect(source!.sourceInfo.name, contains('JS 待支持'));
    });

    test('returns null for empty content', () {
      expect(LxMusicAdapter.tryCreate(''), isNull);
    });

    test('extracts name from JS', () {
      final source = LxMusicAdapter.tryCreate('const name = "Netease";');
      expect(source!.sourceInfo.name, contains('Netease'));
    });
  });
}