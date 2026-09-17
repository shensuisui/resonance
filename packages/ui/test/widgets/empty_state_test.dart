/// EmptyState Widget 测试
///
/// 对应 lib/src/widgets/empty_state.dart。
/// 验证：
/// - 默认图标为 Icons.search_off
/// - 自定义图标生效
/// - message 文本渲染且居中
///
/// 模拟数据来源：纯展示组件，无外部依赖。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: child));

  group('EmptyState', () {
    testWidgets('默认图标为 search_off，显示 message', (tester) async {
      await tester.pumpWidget(wrap(const EmptyState(message: '没有找到歌曲')));

      expect(find.byIcon(Icons.search_off), findsOneWidget);
      expect(find.text('没有找到歌曲'), findsOneWidget);
    });

    testWidgets('自定义图标生效', (tester) async {
      await tester.pumpWidget(wrap(const EmptyState(
        icon: Icons.music_off,
        message: '播放列表为空',
      )));

      expect(find.byIcon(Icons.music_off), findsOneWidget);
      expect(find.byIcon(Icons.search_off), findsNothing);
      expect(find.text('播放列表为空'), findsOneWidget);
    });

    testWidgets('内容居中显示（Center 包裹）', (tester) async {
      await tester.pumpWidget(wrap(const EmptyState(message: '空')));

      // 行为断言：文本实际水平居中于画布
      // （不按 Center 数量断言：新版 Flutter 的 Icon 内部也含 Center，
      //   find.descendant 会命中外层 Center + Icon 内置 Center 共 2 个）
      final textRect = tester.getRect(find.text('空'));
      final canvasSize = tester.getSize(find.byType(Scaffold));
      expect(textRect.center.dx, closeTo(canvasSize.width / 2, 1));

      // 图标与文字纵向排列（Column 结构，限定在 EmptyState 子树内）
      expect(
        find.descendant(
          of: find.byType(EmptyState),
          matching: find.byType(Column),
        ),
        findsOneWidget,
      );
    });

    testWidgets('长文本不溢出（800x600 默认画布）', (tester) async {
      // 边界：超长 message 应在默认测试画布内正常渲染不报 overflow
      await tester.pumpWidget(wrap(const EmptyState(
        message: '这是一段非常长的空状态提示文本，用于验证布局在极端内容下不会出现溢出错误',
      )));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('hint 与主操作按钮展示并触发回调', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(wrap(EmptyState(
        icon: Icons.history_rounded,
        message: '还没有播放记录',
        hint: '播放过的歌曲会出现在这里',
        actionLabel: '去搜索',
        onAction: () => tapped++,
      )));

      expect(find.text('还没有播放记录'), findsOneWidget);
      expect(find.text('播放过的歌曲会出现在这里'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '去搜索'), findsOneWidget);

      await tester.tap(find.text('去搜索'));
      expect(tapped, 1);
    });

    testWidgets('未提供 onAction 时不显示按钮', (tester) async {
      await tester.pumpWidget(wrap(const EmptyState(
        message: '空',
        actionLabel: '不应出现',
      )));
      expect(find.text('不应出现'), findsNothing);
    });
  });
}
