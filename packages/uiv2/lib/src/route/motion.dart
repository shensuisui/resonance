/// iOS 27 风格卡片转场的物理与常量
library;

import 'package:flutter/physics.dart';

/// 推入弹簧：300ms 临界阻尼
final SpringDescription pushSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 300),
);

/// 推入初速（距离/秒，归一化到 0..1）
const double pushSpeed = 9.0;

/// 收敛容差
const Tolerance settleTolerance = Tolerance(distance: 1e-3, velocity: 1e-2);

/// 由弹簧+初速求真实动画时长（不写死 300ms）
Duration settlingTimeOf(SpringDescription spring, double launchSpeed) {
  final sim = SpringSimulation(spring, 0, 1, launchSpeed, tolerance: settleTolerance);
  var ms = 0;
  while (!sim.isDone(ms / 1000)) {
    ms++;
  }
  return Duration(milliseconds: ms);
}

/// 在到达 0/1 时立刻结束的弹簧（不允许停在过冲点）
class ArrivingSimulation extends Simulation {
  /// 内层弹簧
  final Simulation inner;

  /// 构造
  ArrivingSimulation(this.inner);

  @override
  double x(double time) => inner.x(time);

  @override
  double dx(double time) => inner.dx(time);

  @override
  bool isDone(double time) {
    final v = inner.x(time);
    if (v <= 0.0 || v >= 1.0) return true;
    return inner.isDone(time);
  }
}

/// 拖拽返回弹簧
final SpringDescription followSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 80),
  bounce: 0.15,
);
final SpringDescription releaseSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 300),
  bounce: 0.15,
);

/// 拖过 46.65% 宽即 pop
const double popReach = 0.4665;

/// 速度按剩余 0.35s 折算
const double popLead = 0.35;

/// 超过 1.5 宽/秒开始加速
const double flickSpeed = 1.5;

/// 最多放大到 4.25 倍
const double flickBoost = 4.25;

/// 触摸起手阈值
const double touchSlop = 30.0;

/// 反向橡皮筋刚度
const double rubberStiffness = 0.55;

/// 橡皮筋上限（0.5 宽）
const double rubberReach = 0.5;

/// 跟随位移（像素）：正向夹到宽度，反向走橡皮筋
double dragOffsetFor(double dx, double width) {
  if (width <= 0) return 0;
  if (dx >= 0) return dx < width ? dx : width;
  final p = -dx / width;
  final fraction = 1 - 1 / (rubberStiffness * p / rubberReach + 1);
  return -fraction * rubberReach * width;
}

/// 松手是否达到 pop 阈值
bool shouldPopFor(double translation, double velocity, double width) =>
    translation + popLead * velocity >= popReach * width;
