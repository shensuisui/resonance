/// PressableScale 按压缩放组件测试
///
/// 验证：
/// 1. 按下时 AnimatedScale 缩小（<1），松开回弹到 1
/// 2. 点击手势触发 onTap
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/src/widgets/pressable_scale.dart';

void main() {
  testWidgets('按下缩小，松开回弹', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressableScale(
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      ),
    );

    // 初始
    expect(_scaleOf(tester), 1.0);

    // 按下
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressableScale)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(_scaleOf(tester), lessThan(1.0));

    // 松开
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 150));
    expect(_scaleOf(tester), 1.0);
  });

  testWidgets('点击触发 onTap', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressableScale(
              onTap: () => tapped++,
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(PressableScale));
    await tester.pumpAndSettle();
    expect(tapped, 1);
  });
}

double _scaleOf(WidgetTester tester) {
  return tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
}
