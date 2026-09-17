/// 波浪进度条 —— 播放进度 + 正弦波浪律动（对标 PixelPlayer WavyMusicSlider）
///
/// 特性：
/// - 播放中已播放段带正弦波浪动画（相位循环），暂停时波平
/// - 拖动/点按时 thumb 放大，可精确 seek；未播放段用轨道底色
/// - 语义保持 Slider 等价（Semantics slider）
///
/// 用法：传入 0~1 的 [value] 与 [isPlaying]，拖动结束回调 [onSeek]。
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';

class WavyProgressBar extends StatefulWidget {
  /// 当前进度（0~1）
  final double value;

  /// 是否播放中（播放中波浪律动）
  final bool isPlaying;

  /// 拖动/点按结束回调（0~1）
  final ValueChanged<double>? onSeek;

  /// 轨道高度
  final double height;

  /// 是否显示 thumb（迷你条等紧凑场景可关闭）
  final bool showThumb;

  final Color? activeColor;
  final Color? trackColor;

  const WavyProgressBar({
    super.key,
    required this.value,
    this.isPlaying = false,
    this.onSeek,
    this.height = 6,
    this.showThumb = true,
    this.activeColor,
    this.trackColor,
  });

  @override
  State<WavyProgressBar> createState() => _WavyProgressBarState();
}

class _WavyProgressBarState extends State<WavyProgressBar>
    with SingleTickerProviderStateMixin {
  /// 波浪相位动画（播放中循环）
  late final AnimationController _wave;

  /// 拖动中的本地进度（null = 未拖动，显示 widget.value）
  double? _dragValue;

  /// 拖动中 thumb 放大反馈
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _syncWave();
  }

  @override
  void didUpdateWidget(covariant WavyProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncWave();
  }

  /// 播放中启动波浪循环，暂停时停止
  void _syncWave() {
    if (widget.isPlaying && !_wave.isAnimating) {
      _wave.repeat();
    } else if (!widget.isPlaying && _wave.isAnimating) {
      _wave.stop();
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  double get _displayValue => _dragValue ?? widget.value;

  void _seekTo(double dx, double width) {
    if (width <= 0) return;
    final v = (dx / width).clamp(0.0, 1.0);
    setState(() => _dragValue = v);
  }

  void _endSeek() {
    final v = _dragValue;
    setState(() {
      _dragging = false;
      _dragValue = null;
    });
    if (v != null) widget.onSeek?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = widget.activeColor ?? cs.primary;
    final track = widget.trackColor ?? cs.surfaceContainerHighest;

    final pct = (_displayValue * 100).round();
    return Semantics(
      slider: true,
      value: '$pct%',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              _seekTo(d.localPosition.dx, width);
              _endSeek();
            },
            onHorizontalDragStart: (d) {
              setState(() => _dragging = true);
              _seekTo(d.localPosition.dx, width);
            },
            onHorizontalDragUpdate: (d) {
              _seekTo(d.localPosition.dx, width);
            },
            onHorizontalDragEnd: (_) => _endSeek(),
            onHorizontalDragCancel: () {
              setState(() {
                _dragging = false;
                _dragValue = null;
              });
            },
            child: SizedBox(
              height: widget.height + (_dragging ? 8 : 0),
              child: AnimatedBuilder(
                animation: _wave,
                builder: (context, _) => CustomPaint(
                  size: Size(width, widget.height),
                  painter: _WavyProgressPainter(
                    value: _displayValue,
                    phase: _wave.value * math.pi * 2,
                    isPlaying: widget.isPlaying,
                    activeColor: active,
                    trackColor: track,
                    height: widget.height,
                    showThumb: widget.showThumb,
                    dragging: _dragging,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 波浪进度条绘制
class _WavyProgressPainter extends CustomPainter {
  final double value;
  final double phase;
  final bool isPlaying;
  final Color activeColor;
  final Color trackColor;
  final double height;
  final bool showThumb;
  final bool dragging;

  _WavyProgressPainter({
    required this.value,
    required this.phase,
    required this.isPlaying,
    required this.activeColor,
    required this.trackColor,
    required this.height,
    required this.showThumb,
    required this.dragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cy = size.height / 2;
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, cy - height / 2, w, height),
      Radius.circular(height / 2),
    );

    // 未播放段轨道
    canvas.drawRRect(trackRect, Paint()..color = trackColor);

    // 已播放段宽度
    final playedW = w * value;
    if (playedW <= 0) {
      if (showThumb) _drawThumb(canvas, Offset(0, cy), w);
      return;
    }

    // 波浪参数：播放中正弦律动，暂停时波平
    final amp = isPlaying ? height * 0.55 : 0.0;
    final freq = math.pi * 2 / 36; // 波长约 36px
    final path = Path();
    path.moveTo(0, cy);
    for (double x = 0; x <= playedW; x += 1.5) {
      final y = cy + math.sin(x * freq + phase) * amp;
      path.lineTo(x, y);
    }
    path.lineTo(playedW, cy);
    path.close();

    canvas.save();
    canvas.clipRRect(trackRect);
    canvas.drawPath(
      path,
      Paint()
        ..color = activeColor
        ..style = PaintingStyle.fill,
    );
    canvas.restore();

    // thumb（拖动时放大）
    if (showThumb) _drawThumb(canvas, Offset(playedW, cy), w);
  }

  void _drawThumb(Canvas canvas, Offset pos, double w) {
    final radius = dragging ? 8.0 : 5.0;
    if (!dragging && pos.dx < 6) return; // 0 进度不画小 thumb
    if (pos.dx > w - 4 && w > 0) return;
    canvas.drawCircle(pos, radius, Paint()..color = Colors.white);
    canvas.drawCircle(pos, radius - 2, Paint()..color = activeColor);
  }

  @override
  bool shouldRepaint(covariant _WavyProgressPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.phase != phase ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.dragging != dragging ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.trackColor != trackColor;
  }
}
