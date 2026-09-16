/// 封面主色提取工具
///
/// 歌单详情头部背景根据封面图主题色着色：
/// - [extract]：对封面像素降采样，取「饱和度最高且亮度适中」的像素为主色，
///   全部过暗/过亮（如纯黑/纯白）时回落平均色。
/// - [foreground]：主色上的前景色（亮度高用深色文字，否则白色）。
/// - [darken]：主色压暗，用于背景渐变。
///
/// 无第三方依赖，纯 dart:ui 像素运算（约 40 行），可单元测试。
library;

import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class CoverPalette {
  CoverPalette._();

  /// 降采样边长（像素）：遍历步长按图片尺寸推算，保证采样点数恒定
  static const int sampleSize = 16;

  /// 从封面图提取主题主色
  static Future<Color> extract(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return Colors.grey;

    final bytes = data.buffer.asUint8List();
    final w = image.width;
    final h = image.height;
    final stepX = (((w / sampleSize).ceil()).clamp(1, w)).toInt();
    final stepY = (((h / sampleSize).ceil()).clamp(1, h)).toInt();

    double rSum = 0, gSum = 0, bSum = 0;
    var count = 0;
    Color? best;
    var bestScore = -1.0;

    for (var y = 0; y < h; y += stepY) {
      final row = y * w * 4;
      for (var x = 0; x < w; x += stepX) {
        final i = row + x * 4;
        final r = bytes[i] / 255.0;
        final g = bytes[i + 1] / 255.0;
        final b = bytes[i + 2] / 255.0;
        rSum += r;
        gSum += g;
        bSum += b;
        count++;

        final maxC = r > g ? (r > b ? r : b) : (g > b ? g : b);
        final minC = r < g ? (r < b ? r : b) : (g < b ? g : b);
        final l = (maxC + minC) / 2;
        final s = maxC == 0 ? 0.0 : (maxC - minC) / maxC;

        // 亮度适中优先；同亮度下饱和度越高越接近封面主视觉
        if (l >= 0.15 && l <= 0.85) {
          final score = s * (1.0 - (l - 0.5).abs() * 1.2);
          if (score > bestScore) {
            bestScore = score;
            best = Color.from(red: r, green: g, blue: b, alpha: 1);
          }
        }
      }
    }

    if (best != null) return best;
    if (count == 0) return Colors.grey;
    return Color.from(
      red: rSum / count,
      green: gSum / count,
      blue: bSum / count,
      alpha: 1,
    );
  }

  /// 主色上的前景色：相对亮度 > 0.55 用深色文字，否则白色
  static Color foreground(Color background) {
    final l = background.r * 0.299 +
        background.g * 0.587 +
        background.b * 0.114;
    return l > 0.55 ? Colors.black87 : Colors.white;
  }

  /// 主色向黑色压暗 [amount]（0~1），用于渐变背景底部
  static Color darken(Color color, double amount) {
    return Color.lerp(color, Colors.black, amount)!;
  }
}
