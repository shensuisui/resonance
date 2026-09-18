/// EmptyState 空态/错误态组件测试
///
/// 对应 lib/src/widgets/empty_state.dart。
/// 验证：
/// - 普通空态：message + hint + 可选主操作按钮
/// - error 命名构造：错误图标、错误色文案、重试按钮回调
/// - 横屏可用高度小时不溢出（SingleChildScrollView 兜底）
///
/// 模拟数据：内联字符串与回调，不依赖 provider。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('普通空态渲染 message 与 hint', (tester) async {
    await tester.pumpWidget(wrap(const EmptyState(
      icon: Icons.queue_music_rounded,
      message: '队列为空',
      hint: '播放歌曲后自动加入队列',
    )));

    expect(find.text('队列为空'), findsOneWidget);
    expect(find.text('播放歌曲后自动加入队列'), findsOneWidget);
    expect(find.byIcon(Icons.queue_music_rounded), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing, reason: '无操作时不出按钮');
  });

  testWidgets('提供 actionLabel 时显示主操作按钮并可点击', (tester) async {
    var tapped = false;
    await tester.pumpWidget(wrap(EmptyState(
      message: '还没有歌单',
      actionLabel: '新建歌单',
      actionIcon: Icons.add_rounded,
      onAction: () => tapped = true,
    )));

    await tester.tap(find.text('新建歌单'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('error 构造显示错误图标/详情/重试', (tester) async {
    var retried = false;
    await tester.pumpWidget(wrap(EmptyState.error(
      message: '加载失败',
      detail: 'SocketException: 连接被拒绝',
      onRetry: () => retried = true,
    )));

    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.text('加载失败'), findsOneWidget);
    expect(find.textContaining('SocketException'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(retried, isTrue);
  });

  testWidgets('无 onRetry 的 error 不显示重试按钮', (tester) async {
    await tester.pumpWidget(wrap(const EmptyState.error(message: '出错了')));
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('横屏矮可用高度下不溢出', (tester) async {
    tester.view.physicalSize = const Size(900, 320);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const EmptyState(
      icon: Icons.person_off_rounded,
      message: '未找到「周杰伦」的相关歌曲',
      hint: '换个关键词再搜一次',
    )));
    await tester.pump();

    expect(tester.takeException(), isNull, reason: '矮屏下应可滚动而非溢出');
  });
}
