/// iOS 27 卡片推入转场：新页位移入场，被覆盖页左移 30% 并变暗 10%
library;

import 'dart:math' as math;
import 'dart:ui' show Clip;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';

import 'drag_back.dart';
import 'motion.dart';

/// 卡片推入的固定时长（由弹簧推出，约 459ms）
final Duration cardSettleDuration = settlingTimeOf(pushSpring, pushSpeed);

/// 给 PageRoute 装上卡片推入 + 拖拽返回
mixin CardRouteMixin<T> on DragBackRouteMixin<T> {
  @override
  Duration get transitionDuration => cardSettleDuration;

  @override
  Duration get reverseTransitionDuration => cardSettleDuration;

  /// 两个方向都用同一根弹簧；pop 时用控制器当前速度，保证中断不跳变
  @override
  Simulation? createSimulation({required bool forward}) {
    final c = controller;
    if (c == null) return null;
    final velocity = forward ? pushSpeed : c.velocity;
    return ArrivingSimulation(
      SpringSimulation(
        pushSpring,
        c.value,
        forward ? 1.0 : 0.0,
        velocity,
        tolerance: settleTolerance,
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final radius = MediaQuery.maybeDisplayCornerRadiiOf(context) ?? BorderRadius.zero;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return dragBackDetector(
      ValueListenableBuilder<bool>(
        valueListenable: isDragBackActive,
        builder: (context, active, _) {
          if (active) {
            return dragBackSlide(animation, child);
          }
          return _CardTransition(
            animation: animation,
            secondaryAnimation: secondaryAnimation,
            overdrag: overdrag,
            radius: radius,
            devicePixelRatio: dpr,
            child: child,
          );
        },
      ),
    );
  }
}

/// 卡片位移 RenderObject 的 Widget 包装
class _CardTransition extends SingleChildRenderObjectWidget {
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final ValueNotifier<double> overdrag;
  final BorderRadius radius;
  final double devicePixelRatio;

  const _CardTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.overdrag,
    required this.radius,
    required this.devicePixelRatio,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderCardTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        overdrag: overdrag,
        radius: radius,
        devicePixelRatio: devicePixelRatio,
        textDirection: Directionality.of(context),
      );

  @override
  void updateRenderObject(BuildContext context, _RenderCardTransition renderObject) {
    renderObject
      ..animation = animation
      ..secondaryAnimation = secondaryAnimation
      ..overdrag = overdrag
      ..radius = radius
      ..devicePixelRatio = devicePixelRatio
      ..textDirection = Directionality.of(context);
  }
}

class _RenderCardTransition extends RenderProxyBox {
  _RenderCardTransition({
    required Animation<double> animation,
    required Animation<double> secondaryAnimation,
    required ValueNotifier<double> overdrag,
    required BorderRadius radius,
    required double devicePixelRatio,
    required TextDirection textDirection,
  })  : _animation = animation,
        _secondaryAnimation = secondaryAnimation,
        _overdrag = overdrag,
        _radius = radius,
        _devicePixelRatio = devicePixelRatio,
        _textDirection = textDirection {
    _animation.addListener(_onTick);
    _secondaryAnimation.addListener(_onTick);
    _overdrag.addListener(_onTick);
  }

  Animation<double> _animation;
  Animation<double> _secondaryAnimation;
  ValueNotifier<double> _overdrag;
  BorderRadius _radius;
  double _devicePixelRatio;
  TextDirection _textDirection;

  set animation(Animation<double> value) {
    if (identical(value, _animation)) return;
    _animation.removeListener(_onTick);
    _animation = value..addListener(_onTick);
    _onTick();
  }

  set secondaryAnimation(Animation<double> value) {
    if (identical(value, _secondaryAnimation)) return;
    _secondaryAnimation.removeListener(_onTick);
    _secondaryAnimation = value..addListener(_onTick);
    _onTick();
  }

  set overdrag(ValueNotifier<double> value) {
    if (identical(value, _overdrag)) return;
    _overdrag.removeListener(_onTick);
    _overdrag = value..addListener(_onTick);
    _onTick();
  }

  set radius(BorderRadius value) {
    if (value == _radius) return;
    _radius = value;
    _onTick();
  }

  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    _onTick();
  }

  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    _onTick();
  }

  void _onTick() {
    if (attached) markNeedsPaint();
  }

  TransformLayer? _transformLayer;
  ClipRSuperellipseLayer? _clipLayer;

  double get _covered => _secondaryAnimation.value;

  double _dxFor(Size size) {
    var dx = (1 - _animation.value - _overdrag.value) * size.width;
    dx = (dx * _devicePixelRatio).round() / _devicePixelRatio;
    if (_textDirection == TextDirection.rtl) dx = -dx;
    return dx;
  }

  double _coveredDxFor(Size size) {
    final covered = math.min(_covered, 1.0);
    var dx = -0.3 * size.width * covered;
    dx = (dx * _devicePixelRatio).round() / _devicePixelRatio;
    if (_textDirection == TextDirection.rtl) dx = -dx;
    return dx;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final size = this.size;
    final dx = _dxFor(size);
    final coveredDx = _coveredDxFor(size);
    final settled = _animation.isCompleted && _covered == 0;
    if (settled) {
      _transformLayer = null;
      _clipLayer = null;
      super.paint(context, offset);
      return;
    }

    final translate = coveredDx + dx;
    final oldTransform = _transformLayer?.attached == true ? _transformLayer : null;
    final oldClip = _clipLayer?.attached == true ? _clipLayer : null;
    _transformLayer = context.pushTransform(
      needsCompositing,
      offset,
      Matrix4.translationValues(translate, 0, 0),
      (context, offset) {
        _paintShadow(context, size, dx);
        final rect = Offset.zero & size;
        final shape = _shapeFor(rect, _radius);
        _clipLayer = context.pushClipRSuperellipse(
          needsCompositing,
          offset,
          rect,
          shape,
          (context, offset) {
            super.paint(context, offset);
            if (_covered > 0) {
              final paint = Paint()
                ..color = Color.from(
                  alpha: 0.1 * math.min(_covered, 1.0),
                  red: 0,
                  green: 0,
                  blue: 0,
                );
              context.canvas.drawRect(offset & size, paint);
            }
          },
          clipBehavior: Clip.hardEdge,
          oldLayer: oldClip,
        );
      },
      oldLayer: oldTransform,
    );
  }

  void _paintShadow(PaintingContext context, Size size, double dx) {
    if (_animation.isCompleted) return;
    if (dx == 0) return;
    // 前缘外侧线性渐变；4% 黑；sigma 12；宽 3×sigma
    const sigma = 12.0;
    const width = 3 * sigma;
    const stops = <double>[0, 1 / 6, 1 / 3, 1 / 2, 2 / 3, 1];
    const factors = <double>[0.5, 0.3085, 0.1587, 0.0668, 0.0228, 0.0];
    final colors = <Color>[
      for (final f in factors) Color.from(alpha: 0.04 * f, red: 0, green: 0, blue: 0),
    ];
    final left = dx > 0;
    final rect = Rect.fromLTWH(
      left ? -width : size.width,
      0,
      width,
      size.height,
    );
    final shader = LinearGradient(
      begin: left ? Alignment.centerRight : Alignment.centerLeft,
      end: left ? Alignment.centerLeft : Alignment.centerRight,
      colors: colors,
      stops: stops,
    ).createShader(rect);
    context.canvas.drawRect(rect, Paint()..shader = shader);
  }

  RSuperellipse _shapeFor(Rect rect, BorderRadius radius) {
    return RSuperellipse.fromLTRBAndCorners(
      rect.left,
      rect.top,
      rect.right,
      rect.bottom,
      topLeft: radius.topLeft,
      topRight: radius.topRight,
      bottomRight: radius.bottomRight,
      bottomLeft: radius.bottomLeft,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final dx = _dxFor(size) + _coveredDxFor(size);
    transform.translate(dx, 0.0);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final dx = _dxFor(size) + _coveredDxFor(size);
    final local = position - Offset(dx, 0);
    if (!(Offset.zero & size).contains(local)) return false;
    return super.hitTestChildren(result, position: local);
  }

  @override
  void detach() {
    super.detach();
    _transformLayer = null;
    _clipLayer = null;
  }

  @override
  void dispose() {
    _animation.removeListener(_onTick);
    _secondaryAnimation.removeListener(_onTick);
    _overdrag.removeListener(_onTick);
    super.dispose();
  }
}
