/// 全屏拖拽返回（任意位置起手）
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'motion.dart';

/// 让页面支持横向拖拽返回
///
/// 只负责手势与位移，不改变路由本身；配合 CardRouteMixin 使用。
mixin DragBackRouteMixin<T> on PageRoute<T> {
  /// 超过 1 宽后的额外位移（0..1 比例），供卡片转场叠加
  final ValueNotifier<double> overdrag = ValueNotifier<double>(0);

  /// 是否正在拖拽（拖拽时改用横向滑动而不是淡入）
  final ValueNotifier<bool> isDragBackActive = ValueNotifier<bool>(false);

  FocusNode? _focusBeforeDrag;

  /// 页面被拖拽后的横向滑动呈现
  Widget dragBackSlide(Animation<double> animation, Widget child) =>
      SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      );

  /// 包住整页的手势检测器
  Widget dragBackDetector(Widget child) =>
      _DragBackDetector(route: this, child: child);

  double _dragged = 0;
  bool _gestureActive = false;

  /// 手势开始（由 recognizer 调用）
  void handleDragStart() {
    if (!isCurrent || controller == null) return;
    controller!.stop();
    _gestureActive = true;
    isDragBackActive.value = true;
    _dragged = 0;
    _focusBeforeDrag = FocusManager.instance.primaryFocus;
    navigator?.didStartUserGesture();
  }

  /// 手势更新
  void handleDragUpdate(double delta, double width) {
    if (!isDragBackActive.value || width <= 0) return;
    _dragged += delta;
    final dx = _dragged;
    final followed = dragOffsetFor(dx, width);
    overdrag.value = dx > width ? (dx - width) / width : 0;
    final value = (1 - followed / width).clamp(1e-6, 1 - 1e-6);
    controller!.value = value;
  }

  /// 手势结束：判定 pop 或回弹
  Future<void> handleDragEnd(double velocity, double width) async {
    if (!isDragBackActive.value || width <= 0) return;
    final translation = _dragged;
    final shouldPop = shouldPopFor(translation, velocity, width);
    final speed = velocity / width;
    // 速度在 [1, 1.5] 之间线性放大到 4.25 倍
    final t = ((speed.abs() - 1.0) / (flickSpeed - 1.0)).clamp(0.0, 1.0);
    final boost = 1.0 + (flickBoost - 1.0) * t;
    final launch = -(speed * boost);

    if (shouldPop) {
      final sim = SpringSimulation(
        releaseSpring,
        controller!.value,
        0,
        launch,
        tolerance: settleTolerance,
      );
      await controller!.animateWith(ArrivingSimulation(sim)).orCancel
          .catchError((Object _) {});
      finishDrag();
      navigator?.pop();
    } else {
      final sim = SpringSimulation(
        releaseSpring,
        controller!.value,
        1,
        0,
        tolerance: settleTolerance,
      );
      await controller!.animateWith(ArrivingSimulation(sim)).orCancel
          .catchError((Object _) {});
      finishDrag();
    }
  }

  /// 结束拖拽状态（恢复焦点、通知 navigator）
  void finishDrag() {
    if (!_gestureActive) {
      isDragBackActive.value = false;
      overdrag.value = 0;
      return;
    }
    _gestureActive = false;
    isDragBackActive.value = false;
    overdrag.value = 0;
    navigator?.didStopUserGesture();
    final focus = _focusBeforeDrag;
    _focusBeforeDrag = null;
    if (focus != null && focus.canRequestFocus) focus.requestFocus();
  }

  @override
  void dispose() {
    overdrag.dispose();
    isDragBackActive.dispose();
    super.dispose();
  }
}

/// 手势检测器
class _DragBackDetector extends StatefulWidget {
  final DragBackRouteMixin<dynamic> route;
  final Widget child;

  const _DragBackDetector({required this.route, required this.child});

  @override
  State<_DragBackDetector> createState() => _DragBackDetectorState();
}

class _DragBackDetectorState extends State<_DragBackDetector> {
  late final _HorizontalDragBackRecognizer _recognizer =
      _HorizontalDragBackRecognizer(widget.route);

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        _HorizontalDragBackRecognizer:
            GestureRecognizerFactoryWithHandlers<_HorizontalDragBackRecognizer>(
          () => _recognizer,
          (r) {
            r.dragStartBehavior = DragStartBehavior.start;
            r.onStart = (_) {
              widget.route.handleDragStart();
            };
            r.onUpdate = (d) {
              widget.route.handleDragUpdate(
                d.primaryDelta ?? 0,
                MediaQuery.sizeOf(context).width,
              );
            };
            r.onEnd = (d) {
              unawaited(widget.route.handleDragEnd(
                d.velocity.pixelsPerSecond.dx,
                MediaQuery.sizeOf(context).width,
              ));
            };
            r.onCancel = () {
              widget.route.finishDrag();
            };
          },
        ),
      },
      child: widget.child,
    );
  }
}

/// 横向拖拽识别器：起手阈值 30（桌面按 pan slop），不抢横向滚动/输入框
class _HorizontalDragBackRecognizer extends HorizontalDragGestureRecognizer {
  _HorizontalDragBackRecognizer(this._route);

  final DragBackRouteMixin<dynamic> _route;

  @override
  bool isPointerAllowed(PointerEvent event) {
    return _route.isCurrent && super.isPointerAllowed(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? devicePixelRatio,
  ) {
    return globalDistanceMoved.abs() >= touchSlop;
  }
}
