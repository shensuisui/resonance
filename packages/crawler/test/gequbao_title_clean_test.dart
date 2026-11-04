/// 歌曲宝标题/艺人清洗回归测试（不联网）
///
/// 背景：歌曲宝（gequbao）站点返回的标题/艺人自带方括号：列表里是「[稻香]」
/// 「[周杰伦]」，详情页是「[素颜]」「[许嵩&何曼婷]」。不清理就会出现
/// 列表与播放条都带括号、看着像解析没剥干净。
///
/// 方案：只在规则文件的表达式后追加清洗段 ##^\[|\]$||##（零代码改动），
/// 这里直接读**真实规则文件**里的表达式，喂一段与站点结构一致的 HTML，
/// 断言清洗后的结果 —— 既锁住规则、也锁住表达式的清洗语义。
///
/// 模拟数据：手写 HTML 片段（结构对齐 span.text-primary / small.text-jade /
/// h1.song-title-styled span / div.song-author-styled）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crawler/crawler.dart';
import 'package:expr/expr.dart';
import 'package:test/test.dart';

/// 取标量：CSS 取值可能返回 List，测试里统一取首个
String _one(dynamic value) {
  if (value is List) return value.isEmpty ? '' : value.first.toString();
  return value?.toString() ?? '';
}

void main() {
  late Map<String, dynamic> rule;

  setUpAll(() {
    initExprEngine();
    rule = jsonDecode(
            File('../../resonance_app/assets/rules/gequbao.json').readAsStringSync())
        as Map<String, dynamic>;
  });

  group('歌曲宝标题/艺人清洗', () {
    test('搜索项：站点自带的方括号被去掉', () {
      final itemRules =
          (rule['search'] as Map<String, dynamic>)['itemRules'] as Map<String, dynamic>;
      const html = '<div class="row no-gutters py-2d5">'
          '<span class="text-primary">[稻香]</span>'
          '<small class="text-jade">[周杰伦]</small></div>';

      expect(_one(evaluate(itemRules['title'] as String, html)), '稻香');
      expect(_one(evaluate(itemRules['artist'] as String, html)), '周杰伦');
    });

    test('详情项：详情页的方括号同样被去掉', () {
      final extract =
          (rule['songDetail'] as Map<String, dynamic>)['steps'][0]['extract']
              as Map<String, dynamic>;
      const html = '<h1 class="song-title-styled"><span>[素颜]</span></h1>'
          '<div class="song-author-styled">[许嵩&amp;何曼婷]</div>';

      expect(_one(evaluate(extract['title'] as String, html)), '素颜');
      expect(_one(evaluate(extract['artist'] as String, html)), '许嵩&何曼婷');
    });


    test('多值命中时取首个元素，而不是 List 的「[x]」表示法', () {
      final itemRules =
          (rule['search'] as Map<String, dynamic>)['itemRules'] as Map<String, dynamic>;
      const html = '<span class="text-primary">稻香</span>'
          '<small class="text-jade">周杰伦</small>';

      // @CSS:...@text 命中时天然是 List；直接 toString 会得到「[稻香]」
      final rawTitle = evaluate(itemRules['title'] as String, html);
      expect(rawTitle, isA<List<dynamic>>(), reason: '多值提取是 List，这是问题的源头');
      expect(parseFieldText(rawTitle), '稻香', reason: '取值必须取首个元素');
      expect(parseFieldText(['稻香', '晴天']), '稻香');
      expect(parseFieldText(const <dynamic>[]), isNull);
      expect(parseFieldText(null), isNull);
    });

    test('本来没有方括号的标题保持原样（清洗段不误伤）', () {
      final itemRules =
          (rule['search'] as Map<String, dynamic>)['itemRules'] as Map<String, dynamic>;
      const html = '<span class="text-primary">晴天</span>'
          '<small class="text-jade">周杰伦</small>';

      expect(_one(evaluate(itemRules['title'] as String, html)), '晴天');
      expect(_one(evaluate(itemRules['artist'] as String, html)), '周杰伦');
    });
  });
}
