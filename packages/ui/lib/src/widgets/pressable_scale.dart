/// 按压微缩放组件
///
/// 按下时子组件缩小到 [pressedScale]，松开回弹 1.0（120ms 缓出）。
/// 用于按钮/卡片等点击元素的轻量手感反馈，不替代 InkWell 涟漪。
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。
library;

import 'package:flutter/material.dart';

class PressableScale extends StatefulWidget {
  final Widget child;

  /// 点击回调（null 时仅缩放无点击语义）
  final VoidCallback? onTap;

  /// 按下时的缩放比例
  final double pressedScale;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.96,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: widget.child,
        ),
      ),
    );
  }
}
