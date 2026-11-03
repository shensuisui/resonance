/// 生成 App 图标正式资产（6 号线宽 8.8%）
///
/// 输出：
///   fm_app/assets/icon/app_icon.png            1024 满底（iOS / Windows / Web / macOS / 旧版 Android）
///   fm_app/assets/icon/app_icon_foreground.png 1024 透明底白标记（Android 自适应图标前景层）
///
/// 精确两色：#C9341C + #FFFFFF，纯几何绘制，零噪点。
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 品牌红（取自现有 logo 的主色）
const _red = Color(0xFFC9341C);

/// 品牌白
const _white = Color(0xFFFFFFFF);

/// 弧线宽（相对边长）——用户选定的 3 号档
const _arcWidth = 0.088;

/// 画 6 号标记：中心圆点 + 左右各一道向外的弧
void _paintMark(Canvas canvas, double side, {required bool background}) {
  if (background) {
    canvas.drawRect(Rect.fromLTWH(0, 0, side, side), Paint()..color = _red);
  }
  final fill = Paint()
    ..color = _white
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;
  final stroke = Paint()
    ..color = _white
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = _arcWidth * side;

  // 圆点随弧宽微调，保持视觉配重（与对照图同一公式）
  final dotR = 0.085 + (_arcWidth - 0.062) * 0.55;
  canvas.drawCircle(Offset(0.5 * side, 0.52 * side), dotR * side, fill);
  final ring = Rect.fromCircle(
    center: Offset(0.5 * side, 0.52 * side),
    radius: 0.235 * side,
  );
  const sweep = math.pi * 0.44;
  canvas.drawArc(ring, -sweep / 2, sweep, false, stroke);
  canvas.drawArc(ring, math.pi - sweep / 2, sweep, false, stroke);
}

Future<void> _write(String path, int size, {required bool background}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  _paintMark(canvas, size.toDouble(), background: background);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  // 顺带出一份 SVG，方便多平台/以后改尺寸
}

/// SVG（同一份几何，纯矢量）
String _svg() {
  const s = 1024;
  const cx = 0.5 * s, cy = 0.52 * s;
  const r = 0.235 * s;
  const dotR = (0.085 + (_arcWidth - 0.062) * 0.55) * s;
  const half = math.pi * 0.44 / 2;
  String arc(double start) {
    final x1 = cx + r * math.cos(start);
    final y1 = cy + r * math.sin(start);
    final x2 = cx + r * math.cos(start + 2 * half);
    final y2 = cy + r * math.sin(start + 2 * half);
    return '<path d="M ${x1.toStringAsFixed(1)} ${y1.toStringAsFixed(1)} '
        'A ${r.toStringAsFixed(1)} ${r.toStringAsFixed(1)} 0 0 1 '
        '${x2.toStringAsFixed(1)} ${y2.toStringAsFixed(1)}" '
        'stroke="#FFFFFF" stroke-width="${(_arcWidth * s).toStringAsFixed(1)}" '
        'stroke-linecap="round" fill="none"/>';
  }
  return '<svg xmlns="http://www.w3.org/2000/svg" width="$s" height="$s" viewBox="0 0 $s $s">'
      '<rect width="$s" height="$s" fill="#C9341C"/>'
      '<circle cx="$cx" cy="$cy" r="${dotR.toStringAsFixed(1)}" fill="#FFFFFF"/>'
      '${arc(-half)}${arc(math.pi - half)}'
      '</svg>';
}

void main() {
  test('生成图标资产', () async {
    const dir = r'G:\\works\\shelli\\fm\\fm_app\\assets\\icon';
    await _write('$dir\\app_icon.png', 1024, background: true);
    await _write('$dir\\app_icon_foreground.png', 1024, background: false);
    File('$dir\\app_icon.svg').writeAsStringSync(_svg());
    expect(File('$dir\\app_icon.png').existsSync(), isTrue);
    expect(File('$dir\\app_icon_foreground.png').existsSync(), isTrue);
    expect(File('$dir\\app_icon.svg').existsSync(), isTrue);
  });
}
