/// 品牌标记（UiV2BrandMark / UiV2BrandRow）的回归测试
///
/// 背景：换了 App 图标后，用户发现侧栏【回响】左边仍然是旧音符 ——
/// 那是「UiV2Icons.note + 圆角方块」临时拼的，和 App 图标不是同一套图形。
/// 这里钉两件事：
///   ① 侧栏品牌行用的必须是 UiV2BrandMark，且**不再**出现 note 图标；
///   ② 标记的几何确实是「左弧 + 圆点 + 右弧」且左右对称（旧音符做不到对称）。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/components/brand_mark.dart';
import 'package:uiv2/src/design/icons.dart';
import 'package:uiv2/src/design/theme.dart';
import 'package:uiv2/src/design/tokens.dart';

/// 深色主题下的前景/底色（测试用固定值，避免依赖令牌实现细节）
const _ink = Color(0xFF160804);
const _accent = Color(0xFFFF5A3C);

/// 用主题包一层（UiV2BrandMark 从 UiV2Theme 取色）
Widget _wrap(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Theme(
        data: UiV2DesignTheme.dark(),
        child: UiV2Scope(
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );

/// 把 RepaintBoundary 渲染成像素
Future<ByteData> _capture(WidgetTester tester, Key key) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  late ByteData data;
  await tester.runAsync(() async {
    final img = await boundary.toImage();
    data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });
  return data;
}

/// 三态分类：1 = 墨（近黑前景），0 = 底（accent 珊瑚），-1 = 过渡带
///
/// 为什么要死区：图形边缘是抗锯齿的，同一个几何在左右两侧落在不同亚像素上，
/// 边缘像素的亮度会差几个数量级单位；用「严格等于某颜色」去断言对称必然假失败。
/// 过渡带里的像素不参与对称断言，真正的不对称（比如旧音符的符头）仍会被抓出来。
int _classify(ByteData px, int width, int x, int y) {
  final i = (y * width + x) * 4;
  // 只认「完全不透明」的像素：圆角外的透明像素 RGB 是全 0（亮度像墨），
  // 而圆角边缘的抗锯齿像素是「半透明 + 偏暗」，两者都会被误判成墨，
  // 曾让「墨迹占比」被算成 100%。方块内部是纯不透明色，不受影响。
  if (px.getUint8(i + 3) < 250) return -1;
  final lum = 0.299 * px.getUint8(i) +
      0.587 * px.getUint8(i + 1) +
      0.114 * px.getUint8(i + 2);
  if (lum < 80) return 1; // 墨
  if (lum > 110) return 0; // 底
  return -1; // 过渡带
}

void main() {
  testWidgets('品牌行用新标记，且不再出现旧音符图标', (tester) async {
    await tester.pumpWidget(_wrap(const UiV2BrandRow()));
    await tester.pump();

    expect(find.byType(UiV2BrandMark), findsOneWidget,
        reason: '品牌行必须用与 App 图标同一份几何的标记');
    expect(find.byType(UiV2Icon), findsNothing,
        reason: '旧标记是 UiV2Icon(note) 拼的，这里不该再有任何图标组件');
    expect(find.text('回响'), findsOneWidget);
    expect(find.text('RESONANCE'), findsOneWidget);
  });

  testWidgets('侧栏收成窄轨时只留标记、不显示字标', (tester) async {
    await tester.pumpWidget(_wrap(const UiV2BrandRow(showName: false)));
    await tester.pump();

    expect(find.byType(UiV2BrandMark), findsOneWidget);
    expect(find.text('回响'), findsNothing);
    expect(find.text('RESONANCE'), findsNothing);
  });

  testWidgets('标记几何：中线恰好三段墨（左弧/圆点/右弧），且左右镜像对称', (tester) async {
    const side = 64.0;
    await tester.pumpWidget(_wrap(
      RepaintBoundary(
        key: const Key('mark'),
        child: const UiV2BrandMark(size: side),
      ),
    ));
    await tester.pump();
    final px = await _capture(tester, const Key('mark'));
    const w = 64; // 与 side 一致（const 上下文里不能用 toInt()）

    // ① 圆角方块的四个角必须是透明的（不是一整块实心矩形）
    for (final (x, y) in [(0, 0), (w - 1, 0), (0, w - 1), (w - 1, w - 1)]) {
      final a = px.getUint8((y * w + x) * 4 + 3);
      expect(a, lessThan(30), reason: '($x,$y) 应在圆角外，应为透明');
    }

    // ② 墨迹应占方块约一半（App 图标里标记约占 56%）
    //    这条能抓住「标记被缩了两遍」那类错误（实测缩两遍时只有 31%）
    var minX = w, maxX = 0;
    for (var y = 0; y < w; y++) {
      for (var x = 0; x < w; x++) {
        if (_classify(px, w, x, y) == 1) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
        }
      }
    }
    final inkRatio = (maxX - minX + 1) / w;
    expect(inkRatio, greaterThan(0.45),
        reason: '标记横向墨迹应占方块 45% 以上，实际 ${inkRatio.toStringAsFixed(2)}');
    expect(inkRatio, lessThan(0.70),
        reason: '标记不应撑满方块，实际 ${inkRatio.toStringAsFixed(2)}');

    // ③ 沿标记中线数连续墨段：应为 3 段（左弧 / 圆点 / 右弧）
    final row = (0.52 * side).round();
    final runs = <int>[];
    var inRun = false;
    var len = 0;
    for (var x = 0; x < w; x++) {
      if (_classify(px, w, x, row) == 1) {
        inRun = true;
        len++;
      } else if (inRun) {
        runs.add(len);
        inRun = false;
        len = 0;
      }
    }
    if (inRun) runs.add(len);
    expect(runs.length, 3,
        reason: '中线应穿过左弧、圆点、右弧共 3 段墨，实际: $runs');

    // ④ 镜像对称：左右同一点必须同为墨或同为底（过渡带跳过）
    //    旧音符的符头偏一侧，这条一定过不了
    for (var y = row - 20; y <= row + 20; y++) {
      for (var x = 0; x < w ~/ 2; x++) {
        final left = _classify(px, w, x, y);
        final right = _classify(px, w, w - 1 - x, y);
        if (left < 0 || right < 0) continue; // 边缘过渡带不参与
        expect(left, right,
            reason: '标记应左右镜像对称，但 ($x,$y) 与 (${w - 1 - x},$y) 不一致');
      }
    }

    // ⑤ 圆点与弧之间必须是底色（说明是「点 + 弧」而不是一整块）
    //    按几何算：弧内缘半径 = 0.235 - 0.088/2 = 0.191，圆点半径 = 0.0993，
    //    所以中线上的空隙落在 x ∈ (0.5-0.191, 0.5-0.0993) × side ≈ 19.8~25.6，取中点
    final gapX = (side * 0.34).round();
    expect(_classify(px, w, gapX, row), 0,
        reason: '圆点与左弧之间（x=$gapX）应露出底色');
  });
}
