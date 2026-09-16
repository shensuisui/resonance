/// 跑马灯文本组件
///
/// 文本宽度超出容器时：延迟 [initialDelay] 后横向往返滚动，
/// 两端叠加 [fadeColor] 渐变遮罩（淡出效果）；不溢出时正常显示。
/// 用于播放页标题、迷你条标题等长文本场景。
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。
library;

import 'dart:async';
import 'package:flutter/material.dart';

class ScrollableText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  /// 两端渐变遮罩色（一般取背景表面色）
  final Color fadeColor;

  /// 滚动启动延迟
  final Duration initialDelay;

  /// 单程滚动时长（往返总时长为其两倍）
  final Duration scrollDuration;

  const ScrollableText({
    super.key,
    required this.text,
    this.style,
    required this.fadeColor,
    this.initialDelay = const Duration(seconds: 2),
    this.scrollDuration = const Duration(seconds: 4),
  });

  @override
  State<ScrollableText> createState() => _ScrollableTextState();
}

class _ScrollableTextState extends State<ScrollableText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;
  bool _started = false;

  /// 文本超宽量（px，>0 才滚动）
  double _overflow = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant ScrollableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 文本变化：重置滚动状态（重新测量与延迟）
    if (oldWidget.text != widget.text) {
      _reset();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _reset() {
    _started = false;
    _timer?.cancel();
    _controller.stop();
    _controller.value = 0;
  }

  /// 溢出确认后启动滚动（延迟 initialDelay）
  void _start() {
    if (_started || _overflow <= 0) return;
    _started = true;
    _timer?.cancel();
    _timer = Timer(widget.initialDelay, () {
      if (!mounted) return;
      _controller.duration = widget.scrollDuration;
      _controller.repeat(reverse: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (maxWidth.isFinite && maxWidth > 0) {
          final painter = TextPainter(
            text: TextSpan(text: widget.text, style: style),
            maxLines: 1,
            textDirection: TextDirection.ltr,
          )..layout();
          _overflow = painter.width - maxWidth;
        } else {
          _overflow = 0;
        }

        if (_overflow <= 0) {
          // 不溢出：正常单行显示
          return Text(
            widget.text,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        _start();
        return _buildScrolling(style);
      },
    );
  }

  /// 滚动文本 + 两端渐变遮罩
  Widget _buildScrolling(TextStyle style) {
    const fadeWidth = 24.0;
    final fade = widget.fadeColor;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 滚动文本（位移 0 → -overflow 往返）
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final dx = -_controller.value * _overflow;
            return Transform.translate(
              offset: Offset(dx, 0),
              child: Text(
                widget.text,
                style: style,
                maxLines: 1,
                softWrap: false,
              ),
            );
          },
        ),
        // 左端渐变遮罩
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: fadeWidth,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [fade, fade.withValues(alpha: 0)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
          ),
        ),
        // 右端渐变遮罩
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: fadeWidth,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [fade.withValues(alpha: 0), fade],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
