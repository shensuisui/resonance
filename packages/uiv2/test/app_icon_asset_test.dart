/// App 图标资产的回归测试
///
/// 守的是**已发布的那两个 PNG**（fm_app/assets/icon/*.png），不是重新画一遍：
///   ① 尺寸必须是 1024×1024；
///   ② 底色必须精确是品牌红 #C9341C（不是近似色 —— 文生图那批就是每张都偏）；
///   ③ 关键采样点：中心是白色圆点、左右弧位置上必须是白、点与弧之间必须是红。
///
/// 界面上看不到这些，但图标一旦被换成近似色或错位的版本，用户第一眼就会发现。
/// 矢量源在 assets/icon/app_icon.svg（改形状以它为准）。
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// 品牌红
const _red = 0xFFC9341C;

/// 品牌白
const _white = 0xFFFFFFFF;

/// 读一张 PNG 的像素（按 rawRgba）
Future<({int w, int h, ByteData px})> _decode(String path) async {
  final bytes = File(path).readAsBytesSync();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final img = frame.image;
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return (w: img.width, h: img.height, px: data!);
}

/// 取某点颜色（0xAARRGGBB）
int _at(({int w, int h, ByteData px}) img, int x, int y) {
  final i = (y * img.w + x) * 4;
  final r = img.px.getUint8(i);
  final g = img.px.getUint8(i + 1);
  final b = img.px.getUint8(i + 2);
  final a = img.px.getUint8(i + 3);
  return (a << 24) | (r << 16) | (g << 8) | b;
}

void main() {
  // 相对 packages/uiv2 的运行目录
  const png = '../../fm_app/assets/icon/app_icon.png';
  const fg = '../../fm_app/assets/icon/app_icon_foreground.png';

  test('满底图标：1024×1024，底色精确 #C9341C，标记是白色', () async {
    final img = await _decode(png);
    expect(img.w, 1024);
    expect(img.h, 1024);

    // 四角都是品牌红（不是近似色）
    for (final (x, y) in [(4, 4), (1019, 4), (4, 1019), (1019, 1019)]) {
      expect(_at(img, x, y), _red, reason: '角落 ($x,$y) 应是精确的 #C9341C');
    }
    // 中心是白点
    expect(_at(img, 512, 532), _white, reason: '中心应是白色圆点');
    // 左弧中段（角度 π 处）应为白
    expect(_at(img, 271, 532), _white, reason: '左弧应经过 (271,532)');
    // 点与弧之间是红（说明确实留了间隙）
    expect(_at(img, 342, 532), _red, reason: '点与弧之间应是红色空隙');
  });

  test('自适应前景层：同样尺寸，四角透明、标记白色', () async {
    final img = await _decode(fg);
    expect(img.w, 1024);
    expect(img.h, 1024);
    expect(_at(img, 4, 4) & 0xFF000000, 0, reason: '前景层四角必须透明');
    expect(_at(img, 512, 532), _white, reason: '前景层的标记仍是白色');
  });

  test('矢量源存在且声明了两种品牌色', () {
    final svg = File('../../fm_app/assets/icon/app_icon.svg').readAsStringSync();
    expect(svg, contains('#C9341C'));
    expect(svg, contains('#FFFFFF'));
    expect(svg, contains('viewBox="0 0 1024 1024"'));
  });
}
