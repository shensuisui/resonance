/// QueueSheet 播放队列 Sheet 测试
///
/// 对应 lib/src/widgets/queue_sheet.dart。
/// 验证：
/// 1. 空队列显示空态
/// 2. 队列渲染且每项带 Dismissible（滑动删除）与拖拽手柄
/// 3. 左滑删除 → 队列减少 + SnackBar 撤销；点撤销恢复原队列
///
/// 模拟数据：内联歌曲 + playQueueProvider 预置；假播放器记录 setQueue。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:ui/ui.dart';

class _FakePlayer implements Player {
  List<Song> lastQueue = [];

  @override
  Future<void> setQueue(List<Song> queue) async {
    lastQueue = List.from(queue);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  final songs = [
    Song(id: '1', sourceId: 'a', title: '晴天', artist: '周杰伦'),
    Song(id: '2', sourceId: 'a', title: '稻香', artist: '周杰伦'),
  ];

  Future<({ProviderContainer container, _FakePlayer player})> pumpQueue(
    WidgetTester tester, {
    List<Song>? queue,
  }) async {
    final player = _FakePlayer();
    final container = ProviderContainer(overrides: [
      playerProvider.overrideWith((ref) => player),
      appDatabaseProvider.overrideWith((ref) => InMemoryDatabaseProvider()),
    ]);
    addTearDown(container.dispose);
    if (queue != null) {
      container.read(playQueueProvider.notifier).setQueue(queue);
    }
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: QueueSheet())),
    ));
    return (container: container, player: player);
  }

  testWidgets('空队列显示空态', (tester) async {
    await pumpQueue(tester);
    expect(find.text('播放队列 (0)'), findsOneWidget);
    expect(find.text('队列为空'), findsOneWidget);
  });

  testWidgets('队列渲染，每项带 Dismissible 与拖拽手柄', (tester) async {
    await pumpQueue(tester, queue: songs);
    expect(find.text('播放队列 (2)'), findsOneWidget);
    expect(find.byType(Dismissible), findsNWidgets(2));
    expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(2));
  });

  testWidgets('左滑删除显示撤销，点撤销恢复', (tester) async {
    final ({ProviderContainer container, _FakePlayer player}) ctx =
        await pumpQueue(tester, queue: songs);

    // 左滑第一项删除
    await tester.drag(find.text('晴天'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    // 队列减少 + SnackBar 撤销
    expect(
      ctx.container.read(playQueueProvider).length,
      1,
      reason: '删除后队列剩 1 首',
    );
    expect(find.textContaining('已移除'), findsOneWidget);

    // 撤销恢复
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(
      ctx.container.read(playQueueProvider).length,
      2,
      reason: '撤销后队列恢复 2 首',
    );
    expect(ctx.player.lastQueue.length, 2);
  });
}
