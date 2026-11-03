/// 临时：App 图标 6 号（圆点 + 左右对称弧）的线宽分档对照
/// 精确两色 #C9341C + #FFFFFF；出图后本文件删除，正式资产用同一份几何生成。
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 品牌红（取自现有 logo）
const _red = Color(0xFFC9341C);

/// 品牌白
const _white = Color(0xFFFFFFFF);

/// 六号的几何：中心圆点 + 左右各一道向外的弧
/// [arcWidth] 是弧线宽（相对边长）
void paintTwinArc(Canvas canvas, double side, {required double arcWidth}) {
  final fill = Paint()
    ..color = _white
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;
  final stroke = Paint()
    ..color = _white
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = arcWidth * side;

  canvas.drawRect(Rect.fromLTWH(0, 0, side, side), Paint()..color = _red);
  // 中心点随弧线一起微调，保持视觉重量平衡
  final dotR = 0.085 + (arcWidth - 0.062) * 0.55;
  canvas.drawCircle(Offset(0.5 * side, 0.52 * side), dotR * side, fill);
  final ring = Rect.fromCircle(
    center: Offset(0.5 * side, 0.52 * side),
    radius: 0.235 * side,
  );
  const sweep = math.pi * 0.44;
  canvas.drawArc(ring, -sweep / 2, sweep, false, stroke);
  canvas.drawArc(ring, math.pi - sweep / 2, sweep, false, stroke);
}

/// 带圆角的一格（启动器会自己裁圆角，这里只为预览好看）
Widget _tile(double side, double arcWidth) => SizedBox(
      width: side,
      height: side,
      child: CustomPaint(
        painter: _P(arcWidth),
        size: Size(side, side),
      ),
    );

class _P extends CustomPainter {
  final double arcWidth;
  const _P(this.arcWidth);
  @override
  void paint(Canvas canvas, Size size) =>
      paintTwinArc(canvas, size.width, arcWidth: arcWidth);
  @override
  bool shouldRepaint(_P o) => o.arcWidth != arcWidth;
}

void main() {
  setUpAll(() async {
    final bytes = File(r'C:\\Windows\\Fonts\\simhei.ttf').readAsBytesSync();
    final loader = FontLoader('Hei')
      ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    await loader.load();
  });

  testWidgets('6 号线宽分档', (tester) async {
    tester.view.physicalSize = const Size(1000, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 0.062 = 现在；往后逐档加粗
    const widths = [0.062, 0.075, 0.088, 0.100];
    Widget cell(double w, int i) => Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(i == 0 ? '现在' : '${i + 1}',
                  style: const TextStyle(
                      fontFamily: 'Hei', fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: _tile(200, w),
              ),
              const SizedBox(height: 8),
              Text('弧宽 ${(w * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontFamily: 'Hei', fontSize: 12)),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: _tile(48, w),
              ),
              const SizedBox(height: 4),
              const Text('48px',
                  style: TextStyle(fontFamily: 'Hei', fontSize: 11)),
            ],
          ),
        );

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF6F7F9),
        body: Center(
          child: RepaintBoundary(
            key: const Key('preview'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widths.length; i++) cell(widths[i], i),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('preview')),
      matchesGoldenFile('../../../.dsh/tmp/app_icons/v6_widths.png'),
    );
  });
}
