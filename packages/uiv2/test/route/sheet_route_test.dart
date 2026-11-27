/// 大屏 sheet 路由：宽度公式、时长、表单弹簧曲线
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/sheet/form_sheet_route.dart';
import 'package:uiv2/src/sheet/side_sheet_route.dart';

void main() {
  test('侧边 sheet 宽度：800/1200/1600 分别为 360/480/560', () {
    expect(sideSheetWidthFor(800), 360);
    expect(sideSheetWidthFor(1200), 480);
    expect(sideSheetWidthFor(1600), 560);
  });

  test('侧边 sheet：进入 300ms / 退出 200ms', () {
    final route = SideSheetRoute<void>(builder: (_) => const SizedBox());
    expect(route.transitionDuration, const Duration(milliseconds: 300));
    expect(route.reverseTransitionDuration, const Duration(milliseconds: 200));
    route.dispose();
  });

  test('表单 sheet：404ms，曲线 0→1 且单调', () {
    final route = FormSheetRoute<void>(builder: (_) => const SizedBox());
    expect(route.transitionDuration, const Duration(milliseconds: 404));
    expect(route.reverseTransitionDuration, const Duration(milliseconds: 404));
    route.dispose();

    const curve = FormSheetCurve();
    expect(curve.transform(0), closeTo(0, 0.05));
    expect(curve.transform(1), closeTo(1, 0.001));
    var last = -1.0;
    for (var i = 0; i <= 20; i++) {
      final v = curve.transform(i / 20);
      expect(v, greaterThanOrEqualTo(last - 1e-6));
      last = v;
    }
  });
}
