/// QueueSongRow 队列行卡片测试
///
/// 对应 lib/src/widgets/queue_song_row.dart。
/// 队列 Sheet 与队列页共用该组件，样式需与 SongTile 卡片一致：
/// - 普通项：surfaceContainerLow 卡片容器，左侧显示序号
/// - 当前播放项：primaryContainer 高亮，左侧显示 EQ 图标
/// - 点击触发 onTap，trailing 原样渲染
///
/// 模拟数据：内联构造的标题/歌手字符串，不依赖 provider。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

void main() {
  /// 用 MaterialApp 包裹被测组件（需要 Theme）
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  /// 读取 QueueSongRow 外层卡片的装饰色
  Color? cardColor(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.ancestor(
        of: find.byType(InkWell),
        matching: find.byType(Container),
      ).first,
    );
    return (container.decoration as BoxDecoration?)?.color;
  }

  testWidgets('普通项显示序号与标题/歌手', (tester) async {
    await tester.pumpWidget(wrap(const QueueSongRow(
      index: 2,
      title: '晴天',
      artist: '周杰伦',
      isCurrent: false,
    )));

    expect(find.text('3'), findsOneWidget, reason: '序号从 1 开始展示');
    expect(find.text('晴天'), findsOneWidget);
    expect(find.text('周杰伦'), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsNothing);
  });

  testWidgets('当前播放项高亮并显示 EQ', (tester) async {
    final theme = ThemeData(useMaterial3: true);
    await tester.pumpWidget(wrap(QueueSongRow(
      index: 0,
      title: '稻香',
      artist: '周杰伦',
      isCurrent: true,
      onTap: () {},
    )));

    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    expect(find.text('1'), findsNothing, reason: '当前播放项用 EQ 替换序号');
    expect(cardColor(tester), theme.colorScheme.primaryContainer);
  });

  testWidgets('点击触发 onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(wrap(QueueSongRow(
      index: 0,
      title: '晴天',
      artist: '周杰伦',
      isCurrent: false,
      onTap: () => tapped = true,
    )));

    await tester.tap(find.byType(InkWell));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('trailing 原样渲染', (tester) async {
    await tester.pumpWidget(wrap(const QueueSongRow(
      index: 0,
      title: '晴天',
      artist: '周杰伦',
      isCurrent: false,
      trailing: Icon(Icons.drag_handle_rounded),
    )));

    expect(find.byIcon(Icons.drag_handle_rounded), findsOneWidget);
  });
}
