/// 搜索页防抖 = 1000ms（用户定的时长）
///
/// 为什么用 widget 测试而不是真机取样：Flan 的 enter_text 是直接改 controller，
/// **不触发 TextField.onChanged**（真机实测：输入框里已有「周杰伦」，页面却仍是
/// 「最近搜索/推荐」空态，搜索根本没启动）。只有 tester.enterText / 真人输入
/// 才走 onChanged，所以防抖这条链路只能在 widget 测试里验。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:uiv2/src/design/theme.dart';
import 'package:uiv2/src/design/tokens.dart';
import 'package:uiv2/src/pages/search_page.dart';
import 'package:uiv2/src/providers/providers.dart';

/// 只数「搜了几次」的最小替身：不带任何音乐源，搜索立刻收尾
class _CountingManager extends SourceManager {
  /// 被调用 searchStream 的次数
  int calls = 0;

  /// 实际收到的关键词
  final List<String> keywords = [];

  @override
  List<MusicSource> getEnabledSources() => const [];

  @override
  Stream<SearchResult> searchStream({
    required String keyword,
    int page = 1,
    int pageSize = 20,
  }) {
    calls++;
    keywords.add(keyword);
    return const Stream.empty();
  }
}

/// 挂载搜索页
Future<_CountingManager> _pump(WidgetTester tester) async {
  final manager = _CountingManager();
  final db = InMemoryDatabaseProvider();
  await db.initialize();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        sourceManagerProvider.overrideWithValue(manager),
      ],
      child: MaterialApp(
        theme: UiV2DesignTheme.dark(),
        builder: (context, child) =>
            child == null ? const SizedBox() : UiV2Scope(child: child),
        home: const Scaffold(body: SearchPage()),
      ),
    ),
  );
  await tester.pump();
  return manager;
}

void main() {
  testWidgets('输入后 1000ms 才发搜索：不到时长不发', (tester) async {
    final manager = await _pump(tester);

    await tester.enterText(find.byKey(const ValueKey('search_input')), '周杰伦');
    await tester.pump(const Duration(milliseconds: 900));
    expect(manager.calls, 0, reason: '900ms 还没到防抖时长，不能发请求');

    await tester.pump(const Duration(milliseconds: 150)); // 累计 1050ms
    expect(manager.calls, 1, reason: '到 1000ms 应正好发一次');
    expect(manager.keywords.single, '周杰伦');
    final c = ProviderScope.containerOf(tester.element(find.byType(SearchPage)));
    expect(c.read(searchProvider).keyword, '周杰伦',
        reason: '结果对应的必须是当前输入框里的词');
  });

  testWidgets('连续输入只保留最后一次（防抖合并中间前缀）', (tester) async {
    final manager = await _pump(tester);
    final input = find.byKey(const ValueKey('search_input'));

    await tester.enterText(input, '周');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(input, '周杰');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(input, '周杰伦');
    await tester.pump(const Duration(milliseconds: 1100));

    expect(manager.calls, 1, reason: '中间前缀不该各发一次');
    expect(manager.keywords.single, '周杰伦', reason: '只搜最后输入的那个词');
  });
}
