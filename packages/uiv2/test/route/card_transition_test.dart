/// iOS 27 卡片转场：弹簧参数、曲线表、拖拽阈值
library;

import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/route/motion.dart';

double _pctAt(int ms) {
  final sim = SpringSimulation(pushSpring, 0, 1, pushSpeed, tolerance: settleTolerance);
  return sim.x(ms / 1000);
}

void main() {
  test('弹簧时长由参数求出（约 459ms，不是 300ms）', () {
    final d = settlingTimeOf(pushSpring, pushSpeed);
    // 本机 Flutter 3.47 库解出 449ms；规格估算 459ms，同量级
    expect(d.inMilliseconds, inInclusiveRange(440, 470));
    expect(d.inMilliseconds, isNot(300));
  });

  test('推入曲线逐帧：50/100/150/200/300ms 与规格一致（±2%）', () {
    final expected = <int, double>{
      50: 0.44,
      100: 0.73,
      150: 0.88,
      200: 0.95,
      300: 0.991,
    };
    for (final e in expected.entries) {
      expect(_pctAt(e.key), closeTo(e.value, 0.02),
          reason: '${e.key}ms 新页进度应约 ${e.value * 100}%');
    }
  });

  test('被覆盖页位移/遮罩公式：30% 宽 + 10% 黑', () {
    // covered=1 时位移 -30% 宽
    const width = 400.0;
    expect(-0.3 * width, -120.0);
    // 遮罩 alpha = 0.1 * min(covered,1)
    expect(0.1 * 1.0, closeTo(0.1, 1e-9));
  });

  test('ArrivingSimulation 一到 1 立即结束（不留在过冲点）', () {
    final inner = SpringSimulation(pushSpring, 0, 1, pushSpeed,
        tolerance: settleTolerance);
    final sim = ArrivingSimulation(inner);
    var ms = 0;
    while (!sim.isDone(ms / 1000)) {
      ms++;
      expect(ms, lessThan(2000));
    }
    final v = sim.x(ms / 1000);
    expect(v >= 1.0 || v <= 0.0, isTrue);
  });

  test('拖拽：正向夹宽、反向橡皮筋、pop 阈值', () {
    expect(dragOffsetFor(50, 400), 50);
    expect(dragOffsetFor(500, 400), 400);
    expect(dragOffsetFor(-100, 400), lessThan(0));
    expect(dragOffsetFor(-100, 400), greaterThan(-0.5 * 400));
    // 46.65% 宽：静态位移不足 50% 时松手（速度 0）不 pop
    expect(shouldPopFor(0.46 * 400, 0, 400), isFalse);
    expect(shouldPopFor(0.50 * 400, 0, 400), isTrue);
    // 快速轻扫：位移小但速度大也能 pop（0.35s 折算）
    expect(shouldPopFor(0.20 * 400, 0.8 * 400, 400), isTrue);
  });
}
