/// WavyProgressBar 波浪进度条测试
///
/// 验证：
/// 1. 渲染无异常（含播放中波浪）
/// 2. 点按轨道触发 onSeek（按位置换算比例）
/// 3. 拖动触发 onSeek 且跟手
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/src/widgets/wavy_progress_bar.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('渲染无异常（含播放中波浪）', (tester) async {
    await tester.pumpWidget(wrap(const SizedBox(
      width: 300,
      child: WavyProgressBar(value: 0.6, isPlaying: true),
    )));
    expect(find.byType(WavyProgressBar), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点按轨道中心触发 onSeek≈0.5', (tester) async {
    double? seeked;
    await tester.pumpWidget(wrap(SizedBox(
      width: 200,
      child: WavyProgressBar(value: 0.3, onSeek: (v) => seeked = v),
    )));
    await tester.tap(find.byType(WavyProgressBar));
    expect(seeked, isNotNull);
    expect(seeked!, closeTo(0.5, 0.05));
  });

  testWidgets('拖动结束触发 onSeek（按落点比例）', (tester) async {
    double? seeked;
    await tester.pumpWidget(wrap(SizedBox(
      width: 200,
      child: WavyProgressBar(value: 0.1, onSeek: (v) => seeked = v),
    )));

    final barTopLeft = tester.getTopLeft(find.byType(WavyProgressBar));
    // y 取轨道内（默认高度 6），避免命中不到 GestureDetector
    final gesture = await tester.startGesture(barTopLeft + const Offset(40, 3));
    await tester.pump();
    await gesture.moveTo(barTopLeft + const Offset(120, 3));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(seeked, isNotNull);
    expect(seeked!, closeTo(120 / 200, 0.05));
  });

  testWidgets('暂停时渲染无波浪（无异常）', (tester) async {
    await tester.pumpWidget(wrap(const SizedBox(
      width: 200,
      child: WavyProgressBar(value: 0.5, isPlaying: false),
    )));
    expect(tester.takeException(), isNull);
  });
}
