/// 交互反馈组件 —— 对应原型的 :hover / :active 过渡与 @keyframes。
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// 按压缩放包装 —— 对应原型 .icon-btn:active{transform:scale(.94)}、
/// .play-btn:active{scale(.95)}、.btn:active{scale(.98)}、.card 悬浮上移。
///
/// 鼠标悬浮时也可用 [hoverScale] 表达桌面端的轻微放大。
class UiV2Pressable extends StatefulWidget {
  /// 子组件
  final Widget child;

  /// 按下时的缩放比例（原型默认 .94）
  final double pressedScale;

  /// 是否启用（禁用时不做任何反馈）
  final bool enabled;

  /// 点击回调
  final VoidCallback? onTap;

  /// 悬浮时是否高亮背景（对应 :hover 的 surface-2）
  final Color? hoverColor;

  /// 悬浮/按压时的圆角（用于高亮背景）
  final BorderRadius? radius;

  /// 长按回调（列表项「更多操作」用）
  final VoidCallback? onLongPress;

  /// 构造可按压容器
  const UiV2Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.94,
    this.enabled = true,
    this.hoverColor,
    this.radius,
  });

  @override
  State<UiV2Pressable> createState() => _UiV2PressableState();
}

class _UiV2PressableState extends State<UiV2Pressable> {
  bool _down = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.enabled && (widget.onTap != null || widget.onLongPress != null);
    Widget content = widget.child;

    if (widget.hoverColor != null) {
      content = AnimatedContainer(
        duration: UiV2Motion.d1,
        curve: UiV2Motion.enter,
        decoration: BoxDecoration(
          color: (interactive && _hover) ? widget.hoverColor : const Color(0x00000000),
          borderRadius: widget.radius,
        ),
        child: content,
      );
    }

    content = AnimatedScale(
      duration: UiV2Motion.d1,
      curve: UiV2Motion.enter,
      scale: (interactive && _down) ? widget.pressedScale : 1,
      child: content,
    );

    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: interactive ? (_) => setState(() => _down = true) : null,
        onTapCancel: interactive ? () => setState(() => _down = false) : null,
        onTapUp: interactive ? (_) => setState(() => _down = false) : null,
        onTap: interactive ? widget.onTap : null,
        onLongPress: interactive ? widget.onLongPress : null,
        child: content,
      ),
    );
  }
}

/// 淡入工具 —— 对应 CSS @keyframes fade / toast-in。
class UiV2FadeIn extends StatefulWidget {
  /// 子组件
  final Widget child;

  /// 动画时长
  final Duration duration;

  /// 起始位移（对应 toast-in 的 translateY(12px)）
  final Offset from;

  /// 构造淡入包装
  const UiV2FadeIn({
    super.key,
    required this.child,
    this.duration = UiV2Motion.d2,
    this.from = const Offset(0, 12),
  });

  @override
  State<UiV2FadeIn> createState() => _UiV2FadeInState();
}

class _UiV2FadeInState extends State<UiV2FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: UiV2Motion.enter);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: widget.from,
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}
