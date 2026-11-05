/// 搜索历史的“稳定输入”判定测试。
///
/// 背景：自动搜索由 1 秒防抖触发，不能把 a / ab / abc 都写入历史。
/// 方案是输入停止 2 秒后，仅当输入框、当前搜索结果、候选词仍一致时记录。
/// 这组测试锁定该判定，避免清空或继续输入后把旧词写回历史。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/pages/search_page.dart' show shouldRecordSettledSearch;

void main() {
  group('shouldRecordSettledSearch', () {
    test('输入、已搜索关键词、候选词一致时记录', () {
      expect(
        shouldRecordSettledSearch(
          input: 'Anti-Hero',
          searchedKeyword: 'Anti-Hero',
          candidate: 'Anti-Hero',
        ),
        isTrue,
      );
    });

    test('用户继续输入后，旧候选词不记录', () {
      expect(
        shouldRecordSettledSearch(
          input: 'Anti-Hero live',
          searchedKeyword: 'Anti-Hero',
          candidate: 'Anti-Hero',
        ),
        isFalse,
      );
    });

    test('搜索已清空或切换到新关键词时，旧候选词不记录', () {
      expect(
        shouldRecordSettledSearch(
          input: '',
          searchedKeyword: '',
          candidate: 'Anti-Hero',
        ),
        isFalse,
      );
      expect(
        shouldRecordSettledSearch(
          input: 'Come Together',
          searchedKeyword: 'Come Together',
          candidate: 'Anti-Hero',
        ),
        isFalse,
      );
    });

    test('空白输入永远不记录', () {
      expect(
        shouldRecordSettledSearch(
          input: '   ',
          searchedKeyword: '   ',
          candidate: '   ',
        ),
        isFalse,
      );
    });
  });
}
