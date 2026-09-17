/// CoverImage / ShimmerBox 组件测试
///
/// 验证：
/// 1. 无 URL / 空 URL → 音符占位
/// 2. ShimmerBox 渲染无异常（repeat 动画，仅固定帧 pump）
/// 3. CoverImage 有 URL 时渲染 CachedNetworkImage（测试环境网络 400 → 占位兜底）
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/src/widgets/cover_image.dart';
import 'package:ui/src/widgets/shimmer_box.dart';
import '../support/fake_path_provider.dart';

void main() {
  setUp(() => setupFakePathProvider());
  testWidgets('无 URL 显示音符占位', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: CoverImage(width: 48, height: 48),
      ),
    ));
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空字符串 URL 显示占位', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: CoverImage(url: '', width: 48, height: 48),
      ),
    ));
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
  });

  testWidgets('ShimmerBox 渲染无异常（固定帧）', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ShimmerBox(width: 48, height: 48),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('有 URL 渲染 CachedNetworkImage（失败兜底不崩）', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: CoverImage(
            url: 'https://invalid.example/cover.jpg',
            width: 48,
            height: 48,
          ),
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });
    // 网络失败 → errorWidget 占位（音符图标），不抛异常
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
