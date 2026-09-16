/// CoverPalette 主色提取单元测试
///
/// 模拟数据来源：用 PictureRecorder 绘制纯色/双色矩形生成 ui.Image
/// （不依赖网络与图片文件），验证：
/// 1. 纯色图提取出该色（饱和度最高的像素即主色）
/// 2. 深色/浅色背景的前景色（白/黑）选择
/// 3. darken 压暗方向正确
library;

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/src/widgets/cover_palette.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 绘制纯色图片
  Future<ui.Image> solidImage(Color color, {int w = 100, int h = 100}) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..color = color,
    );
    final image = await recorder.endRecording().toImage(w, h);
    return image;
  }

  group('CoverPalette.extract 主色提取', () {
    test('纯色图提取该色（误差 5%）', () async {
      final img = await solidImage(const Color(0xFFE53935));
      final color = await CoverPalette.extract(img);
      expect(color.r, closeTo(0xE5 / 255.0, 0.05));
      expect(color.g, closeTo(0x39 / 255.0, 0.05));
      expect(color.b, closeTo(0x35 / 255.0, 0.05));
    });

    test('非正方形图片同样生效', () async {
      final img = await solidImage(const Color(0xFF2962FF), w: 200, h: 80);
      final color = await CoverPalette.extract(img);
      expect(color.r, closeTo(0x29 / 255.0, 0.05));
      expect(color.g, closeTo(0x62 / 255.0, 0.05));
      expect(color.b, closeTo(0xFF / 255.0, 0.05));
    });
  });

  group('CoverPalette.foreground 前景色', () {
    test('深色背景 → 白色文字', () {
      expect(CoverPalette.foreground(const Color(0xFF111111)), Colors.white);
    });

    test('浅色背景 → 深色文字', () {
      expect(CoverPalette.foreground(const Color(0xFFEEEEEE)), Colors.black87);
    });
  });

  group('CoverPalette.darken 压暗', () {
    test('压暗后各通道向黑色靠拢', () {
      const base = Color(0xFF88CC44);
      final darker = CoverPalette.darken(base, 0.3);
      expect(darker.r, lessThan(base.r));
      expect(darker.g, lessThan(base.g));
      expect(darker.b, lessThan(base.b));
    });
  });
}
