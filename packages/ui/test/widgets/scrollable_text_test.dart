/// ScrollableText 跑马灯组件测试
///
/// 验证：
/// 1. 短文本不溢出时直接渲染 Text（无滚动结构）
/// 2. 长文本溢出时延迟后开始滚动（Transform.translate 位移变化）
/// 3. 两端渐变遮罩存在
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/src/widgets/scrollable_text.dart';

void main() {
  testWidgets('短文本不滚动，直接显示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: ScrollableText(
              text: '短标题',
              fadeColor: Colors.black,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(Text), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ScrollableText),
        matching: find.byType(Transform),
      ),
      findsNothing,
      reason: '短文本不应有滚动结构',
    );
  });

  testWidgets('长文本延迟后开始滚动', (tester) async {
    const longText = '这是一段非常非常长的标题用于测试跑马灯滚动效果是否正常工作';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            child: ScrollableText(
              text: longText,
              fadeColor: Colors.black,
              initialDelay: const Duration(seconds: 2),
              scrollDuration: const Duration(seconds: 4),
            ),
          ),
        ),
      ),
    );

    // 延迟期内不滚动
    await tester.pump(const Duration(seconds: 1));
    final before = _translateDx(tester);
    expect(before, 0.0);

    // 超过延迟后开始滚动（位移 < 0）
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));
    final during = _translateDx(tester);
    expect(during, lessThan(0.0));

    // 渐变遮罩存在（4 个 DecoratedBox：左右遮罩）
    expect(
      find.byWidgetPredicate(
        (w) => w is DecoratedBox &&
            (w.decoration as BoxDecoration?)?.gradient != null,
      ),
      findsNWidgets(2),
    );
  });
}

/// 取滚动文本当前位移（ScrollableText 子树内 Transform.translate 的 dx）
double _translateDx(WidgetTester tester) {
  final transforms = tester.widgetList<Transform>(
    find.descendant(
      of: find.byType(ScrollableText),
      matching: find.byType(Transform),
    ),
  );
  return transforms.first.transform.getTranslation().x;
}
