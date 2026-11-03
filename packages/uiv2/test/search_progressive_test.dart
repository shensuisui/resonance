/// 搜索：请求竞态与逐源渐进加载的回归测试
///
/// 背景（用户提的两条）：
///   ① 防抖之外还有真问题：并发搜索「谁最后返回谁写 state」，于是出现
///      「输入框是『周杰伦』、结果是『周』」。这里钉住令牌机制。
///   ② 以前用 SourceManager.searchAll（Future.wait 等齐所有源），必须等全部
///      返回才有东西上屏。这里钉住逐源上屏的顺序语义：
///      先按默认顺序摆 loading 占位 → 谁先回来谁先上屏 → 无结果的 tab 消失。
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:uiv2/src/components/surfaces.dart';
import 'package:uiv2/src/design/theme.dart';
import 'package:uiv2/src/design/tokens.dart';
import 'package:uiv2/src/pages/search_page.dart';
import 'package:uiv2/src/providers/providers.dart';

/// 一个可控的源：只需要 sourceInfo
class _FakeSource implements MusicSource {
  @override
  final SourceInfo sourceInfo;

  _FakeSource(String id, String name)
      : sourceInfo = SourceInfo(
          id: id,
          name: name,
          type: SourceType.values.first,
          // 必须显式 true：enabledSourcesProvider 读的就是 manager.isSourceEnabled()，
          // 而它就是由 registerSource 时的这个字段种下的
          enabled: true,
        );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 可控的 SourceManager：默认顺序固定，每个源何时返回由测试用 Completer 决定
///
/// 刻意模仿真实 searchStream 的「谁先完成谁先 emit」，这样才能测出顺序语义。
class _StagedManager extends SourceManager {
  /// 用 [SourceManager.registerSource] 注册：**不要**去覆盖 getAllSources /
  /// getEnabledSources / getSource —— 搜索页经 sourceListProvider 用的是
  /// getAllSources（基类内部 map），只覆盖 getEnabledSources 会让页面以为
  /// 「所有音乐源都已停用」（踩过一次）。
  _StagedManager(List<(String, String)> defs) : _count = defs.length {
    for (final d in defs) {
      registerSource(_FakeSource(d.$1, d.$2));
    }
  }

  /// 源个数（闸门数量按它来）
  final int _count;

  /// keyword → 每个源的放行闸门（与注册顺序同序）
  final Map<String, List<Completer<SearchResult>>> gates = {};

  @override
  Stream<SearchResult> searchStream({
    required String keyword,
    int page = 1,
    int pageSize = 20,
  }) {
    final controller = StreamController<SearchResult>();
    final list = gates.putIfAbsent(
      keyword,
      () => [for (var i = 0; i < _count; i++) Completer<SearchResult>()],
    );
    var pending = list.length;
    for (final c in list) {
      unawaited(
        c.future.then((r) {
          if (controller.isClosed) return;
          controller.add(r);
          pending--;
          if (pending == 0) controller.close();
        }),
      );
    }
    return controller.stream;
  }
}

/// 造一个带 n 首歌的结果
SearchResult _res(String sourceId, int n) => SearchResult(
      sourceId: sourceId,
      songs: [
        for (var i = 0; i < n; i++)
          Song(
            id: '$sourceId-$i',
            sourceId: sourceId,
            title: '曲$i',
            artist: '歌手',
          ),
      ],
    );

/// 让已经排队的微任务跑完（Riverpod 状态更新是同步的，流回调需要让一拍）
Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  late _StagedManager manager;
  late ProviderContainer container;

  setUp(() {
    manager = _StagedManager([('a', 'A源'), ('b', 'B源'), ('c', 'C源')]);
    container = ProviderContainer(overrides: <Override>[
      sourceManagerProvider.overrideWithValue(manager),
    ]);
    addTearDown(container.dispose);
  });

  test('逐源渐进：先按默认顺序摆 loading，谁先回来谁先上屏，无结果的 tab 消失', () async {
    final f = container.read(searchProvider.notifier).search('周杰伦');
    await _tick();

    // ① 立刻就有三个来源的占位（不等任何源返回），顺序 = 默认顺序，全部 loading
    var s = container.read(searchProvider);
    expect(s.pools.map((p) => p.id).toList(), ['a', 'b', 'c'],
        reason: '未返回的源也要先占位，且保持默认顺序');
    expect(s.pools.every((p) => p.loading), isTrue);
    expect(s.anyLoading, isTrue);
    expect(s.activePools, isEmpty, reason: 'loading 的分组不参与结果筛选与计数');

    // ② 让「第三个源」先返回：它应当排到最前，其余仍是默认顺序
    manager.gates['周杰伦']![2].complete(_res('c', 2));
    await _tick();
    s = container.read(searchProvider);
    expect(s.pools.map((p) => p.id).toList(), ['c', 'a', 'b'],
        reason: '先返回的排前面，后面的未返回源保持默认顺序');
    expect(s.pools.first.loading, isFalse);
    expect(s.pools.first.songs.length, 2);
    expect(s.anyLoading, isTrue);

    // ③ 第二个源再返回：排在已完成区的末尾（即第一个源之后、未返回的源之前）
    manager.gates['周杰伦']![1].complete(_res('b', 3));
    await _tick();
    s = container.read(searchProvider);
    expect(s.pools.map((p) => p.id).toList(), ['c', 'b', 'a'],
        reason: '已完成区按返回顺序排，未返回的仍在后面');

    // ③.5 关键回归：结果已经上屏时 total 必须是**实时**的。
    // 它原来只在搜索全部结束时写一次，于是这段窗口里 total 仍是 0 ——
    // 界面据此判定「没有找到」并把来源条一起撤掉（用户报的现象）。
    expect(s.total, s.filteredTotal, reason: 'total 必须实时等于 filteredTotal');
    expect(s.total, greaterThan(0), reason: '已经有结果了，total 不能还是 0');

    // ④ 第一个源返回空结果：它的 tab 自己消失
    manager.gates['周杰伦']![0].complete(_res('a', 0));
    await _tick();
    await f;
    s = container.read(searchProvider);
    expect(s.pools.map((p) => p.id).toList(), ['c', 'b'],
        reason: '没有结果的源不该留下一个空 tab');
    expect(s.loading, isFalse);
    expect(s.anyLoading, isFalse);
    expect(s.filteredTotal, 5, reason: '2 + 3，两条都有结果');
  });

  test('竞态：过期请求迟到的结果不得覆盖新关键词（输入与结果必须一致）', () async {
    // 先搜「周」，再立刻搜「周杰伦」——前者慢、后者快（用户遇到的就是这个组合）
    final oldSearch = container.read(searchProvider.notifier).search('周');
    await _tick();
    final newSearch = container.read(searchProvider.notifier).search('周杰伦');
    await _tick();

    expect(container.read(searchProvider).keyword, '周杰伦');

    // 新请求先返回
    manager.gates['周杰伦']![0].complete(_res('a', 2));
    await _tick();
    expect(container.read(searchProvider).pools.first.songs.length, 2,
        reason: '新请求的 a 已返回（此时 b/c 仍是占位，所以取 first 而不是 single）');

    // 旧请求这时才返回：必须被丢弃
    manager.gates['周']![0].complete(_res('a', 9));
    manager.gates['周']![1].complete(_res('b', 9));
    manager.gates['周']![2].complete(_res('c', 9));
    await _tick();
    var s = container.read(searchProvider);
    expect(s.keyword, '周杰伦', reason: '关键词不许被旧请求改回去');
    // 新请求只回来了 a；b/c 仍应在占位等待（说明旧请求的 9 首没有被塞进来）
    expect(s.pools.map((p) => p.id).toList(), ['a', 'b', 'c']);
    expect(s.pools.first.songs.length, 2, reason: '仍是新请求的 2 首');
    expect(s.pools.every((p) => p.songs.length != 9), isTrue,
        reason: '旧请求（每源 9 首）的结果不许混进当前结果');

    // 放行新请求剩下的两个源，让它正常收尾
    manager.gates['周杰伦']![1].complete(_res('b', 0));
    manager.gates['周杰伦']![2].complete(_res('c', 0));
    await _tick();
    await newSearch;
    await oldSearch;
    s = container.read(searchProvider);
    expect(s.loading, isFalse);
    expect(s.pools.map((p) => p.id).toList(), ['a'],
        reason: 'b/c 对新关键词是空结果，tab 应当消失');
  });

  testWidgets('搜索途中：已到一部分结果时不能显示「没有找到」，来源条也不能消失',
      (tester) async {
    // 复现用户报的时序：第一个源刚回来 → 结果上屏；其余源还在搜。
    // 期望：结果区显示那一批，来源条仍在（含仍在 loading 的源）。
    final mgr = _StagedManager([('a', 'A源'), ('b', 'B源')]);
    final db = InMemoryDatabaseProvider();
    await db.initialize();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          sourceManagerProvider.overrideWithValue(mgr),
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
    final c = ProviderScope.containerOf(tester.element(find.byType(SearchPage)));
    unawaited(c.read(searchProvider.notifier).search('周杰伦'));
    await tester.pump();

    // 只放行 A 源（有结果），B 源仍在 loading
    mgr.gates['周杰伦']![0].complete(_res('a', 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(c.read(searchProvider).pools.first.songs.length, 2,
        reason: 'A 源的结果应当已经上屏');
    expect(find.textContaining('没有找到'), findsNothing,
        reason: '已经有结果了，绝不能再显示「没有找到」');
    // 用 chip 精确定位：源名在结果区标题里也会出现（「来自 1 个源 → A源」），
    // 直接 find.text 会命中两处
    expect(find.widgetWithText(UiV2Chip, 'A源'), findsOneWidget,
        reason: '来源条必须还在');
    expect(find.widgetWithText(UiV2Chip, 'B源'), findsOneWidget,
        reason: '还在搜的源也要占着 tab');

    // 放行 B 源让流收尾，避免留下未完成的 future
    mgr.gates['周杰伦']![1].complete(_res('b', 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  });

  test('空关键词：直接复位成 idle，不发请求', () async {
    await container.read(searchProvider.notifier).search('   ');
    final s = container.read(searchProvider);
    expect(s.keyword, isEmpty);
    expect(s.pools, isEmpty);
    expect(s.loading, isFalse);
  });
}
