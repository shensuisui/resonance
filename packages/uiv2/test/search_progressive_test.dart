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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
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
        );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 可控的 SourceManager：默认顺序固定，每个源何时返回由测试用 Completer 决定
///
/// 刻意模仿真实 searchStream 的「谁先完成谁先 emit」，这样才能测出顺序语义。
class _StagedManager extends SourceManager {
  _StagedManager(List<(String, String)> defs)
      : _sources = [for (final d in defs) _FakeSource(d.$1, d.$2)];

  final List<_FakeSource> _sources;

  /// keyword → 每个源的放行闸门（与 _sources 同序）
  final Map<String, List<Completer<SearchResult>>> gates = {};

  @override
  List<MusicSource> getEnabledSources() => List.of(_sources);

  @override
  MusicSource? getSource(String sourceId) =>
      _sources.where((s) => s.sourceInfo.id == sourceId).firstOrNull;

  @override
  Stream<SearchResult> searchStream({
    required String keyword,
    int page = 1,
    int pageSize = 20,
  }) {
    final controller = StreamController<SearchResult>();
    final list = gates.putIfAbsent(
      keyword,
      () => [for (final _ in _sources) Completer<SearchResult>()],
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

  test('空关键词：直接复位成 idle，不发请求', () async {
    await container.read(searchProvider.notifier).search('   ');
    final s = container.read(searchProvider);
    expect(s.keyword, isEmpty);
    expect(s.pools, isEmpty);
    expect(s.loading, isFalse);
  });
}
