import 'package:expr/expr.dart';
import 'package:test/test.dart';

void main() {
  group('CSSParser', () {
    final parser = CSSParser();

    test('parses simple selector', () {
      final result = parser.parse('div.title');
      expect(result.type, ParserType.css);
      expect(result.selector, 'div.title');
      expect(result.extractSuffix, isNull);
    });

    test('parses selector with text suffix', () {
      final result = parser.parse('div.title@text');
      expect(result.selector, 'div.title');
      expect(result.extractSuffix, '@text');
    });

    test('throws on empty expression', () {
      expect(() => parser.parse(''), throwsArgumentError);
    });
  });

  group('JSONPathParser', () {
    final parser = JSONPathParser();

    test('parses dollar prefix', () {
      final result = parser.parse(r'$.data.songs');
      expect(result.type, ParserType.jsonPath);
      expect(result.selector, r'$.data.songs');
    });

    test('parses Json prefix', () {
      final result = parser.parse(r'@Json:$.data.books[0].title');
      expect(result.selector, r'$.data.books[0].title');
    });

    test('throws on empty after prefix', () {
      expect(() => parser.parse('@Json:'), throwsArgumentError);
    });
  });

  group('XPathParser', () {
    final parser = XPathParser();

    test('parses // prefix', () {
      final result = parser.parse("//div[@class='title']/text()");
      expect(result.type, ParserType.xPath);
      expect(result.selector, "//div[@class='title']/text()");
    });

    test('parses XPath prefix', () {
      final result = parser.parse("@XPath://div[@class='title']/text()");
      expect(result.selector, "//div[@class='title']/text()");
    });
  });

  group('RegexParser', () {
    final parser = RegexParser();

    test('parses colon prefix', () {
      final result = parser.parse(r':title\s*:\s*(.*?)\s*\n');
      expect(result.type, ParserType.regex);
      expect(result.selector, r'title\s*:\s*(.*?)\s*\n');
    });

    test('parses Regex prefix', () {
      final result = parser.parse(r'@Regex:title\s*:\s*(.*?)\s*\n');
      expect(result.selector, r'title\s*:\s*(.*?)\s*\n');
    });
  });

  group('ParserFactory', () {
    ParseResult p(String expr) => ParserFactory.parse(expr).parts.first;

    test('routes Json prefix to JSONPath', () {
      final result = p(r'@Json:$.data.songs');
      expect(result.type, ParserType.jsonPath);
    });

    test('routes dollar prefix to JSONPath', () {
      final result = p(r'$.data.songs');
      expect(result.type, ParserType.jsonPath);
    });

    test('routes XPath prefix to XPath', () {
      final result = p('@XPath://div');
      expect(result.type, ParserType.xPath);
    });

    test('routes // to XPath', () {
      final result = p('//div');
      expect(result.type, ParserType.xPath);
    });

    test('routes CSS prefix to CSS', () {
      final result = p('@CSS:div.title@text');
      expect(result.type, ParserType.css);
      expect(result.selector, 'div.title');
    });

    test('routes Regex prefix to Regex', () {
      final result = p('@Regex:pattern');
      expect(result.type, ParserType.regex);
    });

    test('routes colon to Regex', () {
      final result = p(':pattern');
      expect(result.type, ParserType.regex);
    });

    test('defaults to CSS for no prefix', () {
      final result = p('div.title');
      expect(result.type, ParserType.css);
    });

    test('throws on empty expression', () {
      expect(() => ParserFactory.parse(''), throwsArgumentError);
    });
  });

  group('ParserFactory - compound', () {
    test('chain && splits into multiple parts', () {
      final expr = ParserFactory.parse(r'$.data && $.songs');
      expect(expr.compoundType, CompoundType.chain);
      expect(expr.parts.length, 2);
      expect(expr.parts[0].selector, r'$.data');
      expect(expr.parts[1].selector, r'$.songs');
    });

    test('fallback || splits into multiple parts', () {
      final expr = ParserFactory.parse('@CSS:.cover@src || @CSS:.thumb@src');
      expect(expr.compoundType, CompoundType.fallback);
      expect(expr.parts.length, 2);
    });

    test('sanitize ## extracts pattern', () {
      final expr = ParserFactory.parse('div.content##<.*?>||');
      expect(expr.compoundType, CompoundType.none);
      expect(expr.hasSanitize, isTrue);
      expect(expr.sanitizePattern, '<.*?>');
      expect(expr.sanitizeReplacement, '');
    });

    test('sanitize ## with replacement', () {
      final expr = ParserFactory.parse('div.text##old||new');
      expect(expr.sanitizePattern, 'old');
      expect(expr.sanitizeReplacement, 'new');
    });

    test('split # extracts delimiter', () {
      final expr = ParserFactory.parse('div.tags#,');
      expect(expr.hasSplit, isTrue);
      expect(expr.splitChar, ',');
    });

    test('chain with 3+ parts', () {
      final expr = ParserFactory.parse('a && b && c && d');
      expect(expr.compoundType, CompoundType.chain);
      expect(expr.parts.length, 4);
    });
  });

  group('CssEvaluator', () {
    setUp(() {
      initExprEngine();
    });

    test('evaluates CSS selector on HTML', () {
      final html = '<html><body><div class="title">Hello</div></body></html>';
      final result = evaluate('div.title', html);
      expect(result, 'Hello');
    });

    test('evaluates CSS with @text suffix', () {
      final html = '<html><body><div class="item">Item 1</div><div class="item">Item 2</div></body></html>';
      final result = evaluate('div.item@text', html);
      expect(result, ['Item 1', 'Item 2']);
    });

    test('returns null on no match', () {
      final html = '<html><body></body></html>';
      final result = evaluate('div.not-found', html);
      expect(result, isNull);
    });

    test('descendant selector', () {
      final html = '<div class="container"><span class="title">Nested</span></div>';
      final result = evaluate('div.container span.title', html);
      expect(result, 'Nested');
    });

    test('child selector', () {
      final html = '<ul><li class="item">A</li><li class="item">B</li></ul>';
      final result = evaluate('ul > li.item@text', html);
      expect(result, ['A', 'B']);
    });

    test('deep multi-level selector', () {
      final html = '<div id="root"><div><p><a class="link" href="/page">Click</a></p></div></div>';
      final result = evaluate('div#root a.link', html);
      expect(result, 'Click');
    });

    test('attribute selector', () {
      final html = '<input type="text" name="search" value="music">';
      final result = evaluate('input[name="search"]', html);
      expect(result, '');
    });

    test('nested list with @text suffix', () {
      final html = '''
        <div class="list">
          <div class="song"><span class="title">Song A</span><span class="artist">Artist A</span></div>
          <div class="song"><span class="title">Song B</span><span class="artist">Artist B</span></div>
        </div>''';
      final result = evaluate('div.list div.song span.title@text', html);
      expect(result, ['Song A', 'Song B']);
    });
  });

  group('CompoundEvaluator', () {
    setUp(() {
      initExprEngine();
    });

    test('chain &&: passes JSONPath output as input to next', () {
      final data = {'data': {'songs': [{'id': '1', 'title': 'Chain Song'}]}};
      final result = evaluate(r'$.data && $.songs', data);
      expect(result, [{'id': '1', 'title': 'Chain Song'}]);
    });

    test('chain &&: deep path', () {
      final data = {'root': {'items': [{'name': 'Deep'}]}};
      final result = evaluate(r'$.root && $.items', data);
      expect(result, [{'name': 'Deep'}]);
    });

    test('chain && returns null on missing intermediate', () {
      final data = {'a': {'b': 'value'}};
      final result = evaluate(r'$.a && $.missing', data);
      expect(result, isNull);
    });

    test('fallback ||: uses first match', () {
      final html = '<div><img class="cover" src="cover.jpg"></div>';
      final result = evaluate('img.cover@src || img.thumb@src', html);
      expect(result, ['cover.jpg']);
    });

    test('fallback ||: falls back to second', () {
      final html = '<div><img class="thumb" src="thumb.jpg"></div>';
      final result = evaluate('img.cover@src || img.thumb@src', html);
      expect(result, ['thumb.jpg']);
    });

    test('fallback ||: returns null when all fail', () {
      final html = '<div></div>';
      final result = evaluate('img.cover@src || img.thumb@src', html);
      expect(result, isNull);
    });

    test('sanitize ##: removes HTML tags', () {
      final html = '<div class="content"><p>Hello <b>World</b></p></div>';
      final result = evaluate('div.content##<.*?>||', html);
      expect(result, 'Hello World');
    });

    test('sanitize ##: with replacement', () {
      final html = '<div class="text">old word</div>';
      final result = evaluate('div.text##old||new', html);
      expect(result, 'new word');
    });

    test('split #: splits by delimiter', () {
      final html = '<div class="tags">rock, pop, jazz</div>';
      final result = evaluate('div.tags#,', html);
      expect(result, ['rock', 'pop', 'jazz']);
    });

    test('CSS ID selector not mistaken for split', () {
      final html = '<div id="root"><p>Content</p></div>';
      final result = evaluate('div#root', html);
      expect(result, 'Content');
    });

    test('chain + sanitize combined', () {
      final data = {'data': {'html': '<p>A <b>B</b> C</p>'}};
      final result = evaluate(r'$.data && $.html##<.*?>||', data);
      expect(result, 'A B C');
    });
  });

  group('JsonPathEvaluator', () {
    setUp(() {
      initExprEngine();
    });

    test('evaluates JSONPath on Map', () {
      final data = {'data': {'songs': [{'id': '1', 'title': 'Song'}]}};
      final result = evaluate(r'$.data.songs[0].title', data);
      expect(result, 'Song');
    });
  });

  group('RegexEvaluator', () {
    setUp(() {
      initExprEngine();
    });

    test('evaluates regex with capture group', () {
      final text = 'title: Hello World\n';
      final result = evaluate(r':title\s*:\s*(.*?)\s*\n', text);
      expect(result, 'Hello World');
    });
  });

  group('XPathEvaluator', () {
    setUp(() {
      initExprEngine();
    });

    test('evaluates basic XPath', () {
      final xml = '<root><item><title>Hello</title></item></root>';
      final result = evaluate('//item/title', xml);
      expect(result, 'Hello');
    });
  });

  group('initExprEngine', () {
    test('registers all evaluators', () {
      initExprEngine();
      expect(EvaluatorFactory.getEvaluator(ParserType.css), isA<CssEvaluator>());
      expect(EvaluatorFactory.getEvaluator(ParserType.jsonPath), isA<JsonPathEvaluator>());
      expect(EvaluatorFactory.getEvaluator(ParserType.xPath), isA<XPathEvaluator>());
      expect(EvaluatorFactory.getEvaluator(ParserType.regex), isA<RegexEvaluator>());
    });
  });
}