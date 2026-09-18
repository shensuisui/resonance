/// 骨架屏微光组件 —— 图片加载中的占位动画
///
/// 高亮条周期性扫过圆角矩形，模拟加载中状态。
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。
library;

import 'package:flutter/material.dart';

/// 是否处于 UI 自动化（flutter_driver）模式
///
/// 该模式下装饰性无限动画（微光/跳动条/跑马灯）会被静态化：
/// 无限 repeat 会让 flutter_driver 的 tap/pumpAndSettle 永远无法收敛。
const bool kDriverMode = bool.fromEnvironment('FM_DRIVER');

class ShimmerBox extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? radius;

  const ShimmerBox({super.key, this.width, this.height, this.radius});

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    // 驱动模式下保持静态（不 repeat），保证自动化可 settle
    if (!kDriverMode) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = widget.radius ?? BorderRadius.circular(8);
    final base = cs.surfaceContainerHighest;
    final highlight = cs.surfaceContainerHigh;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // 高亮条从 -1.5 扫到 1.5
          final t = _controller.value;
          final begin = Alignment(-1.5 + 3 * t, 0);
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: begin,
                end: Alignment(1.5, 0),
                colors: [base, highlight, base],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          );
        },
      ),
    );
  }
}
