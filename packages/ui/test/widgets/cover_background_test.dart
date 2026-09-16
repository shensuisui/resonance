/// CoverBackground 渐变背景组件测试
///
/// 验证：
/// 1. 无封面（null/空）时渐变整体回退 fallback
/// 2. 封面加载失败（测试环境网络图必然失败）时回退 fallback 不抛异常
/// 网络图在 flutter_test 默认 HttpClient 下返回 400，走失败回退路径。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/src/widgets/cover_background.dart';
import 'package:ui/src/widgets/cover_palette.dart';

/// 取 CoverBackground 内 AnimatedContainer 的渐变颜色列表
List<Color> _gradientColors(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.byType(AnimatedContainer).first,
  );
  final deco = container.decoration! as BoxDecoration;
  return (deco.gradient! as LinearGradient).colors;
}

void main() {
  setUp(() => CoverPalette.debugClearCache());

  testWidgets('无封面时渐变整体回退 fallback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoverBackground(
            coverUrl: null,
            fallback: const Color(0xFF112233),
            child: const SizedBox(),
          ),
        ),
      ),
    );
    final colors = _gradientColors(tester);
    expect(colors[0], const Color(0xFF112233));
    expect(colors[1], const Color(0xFF112233));
  });

  testWidgets('空封面字符串同样回退 fallback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoverBackground(
            coverUrl: '',
            fallback: const Color(0xFF223344),
            child: const SizedBox(),
          ),
        ),
      ),
    );
    final colors = _gradientColors(tester);
    expect(colors[0], const Color(0xFF223344));
    expect(colors[1], const Color(0xFF223344));
  });

  testWidgets('封面加载失败回退 fallback 且不抛异常', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverBackground(
              coverUrl: 'https://invalid.example/cover.jpg',
              fallback: const Color(0xFF445566),
              child: const SizedBox(),
            ),
          ),
        ),
      );
      // 等待 resolveColor 的真实网络失败路径完成
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    final colors = _gradientColors(tester);
    expect(colors[0], const Color(0xFF445566));
    expect(colors[1], const Color(0xFF445566));
  });
}
