/// 大屏居中表单 sheet：404ms，1.2→1 缩放 + 淡入，遮罩同弹簧
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../route/motion.dart';

/// 总时长
const Duration formSheetDuration = Duration(milliseconds: 404);

/// 表单宽度/最大高度/视口边距
const double formSheetWidth = 440;
const double formSheetMaxHeight = 720;
const double formSheetMargin = 40;

/// 内容弹簧（275ms 临界阻尼）
final SpringDescription formSheetSpring =
    SpringDescription.withDurationAndBounce(duration: const Duration(milliseconds: 275));

/// 弹簧曲线：把 0..1 时间映射到弹簧位置
class FormSheetCurve extends Curve {
  /// 构造
  const FormSheetCurve();

  @override
  double transformInternal(double t) {
    final sim = SpringSimulation(formSheetSpring, 0, 1, 0, tolerance: settleTolerance);
    final v = sim.x(t * formSheetDuration.inMilliseconds / 1000);
    return v.clamp(0.0, 1.0);
  }
}

/// 居中表单路由
class FormSheetRoute<T> extends PopupRoute<T> {
  /// 内容
  final WidgetBuilder builder;

  /// 遮罩颜色
  final Color barrierColor;

  /// 构造
  FormSheetRoute({
    required this.builder,
    this.barrierColor = const Color(0x66000000),
    super.settings,
  });

  @override
  Duration get transitionDuration => formSheetDuration;

  @override
  Duration get reverseTransitionDuration => formSheetDuration;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => '关闭';

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    final curved = CurvedAnimation(parent: animation!, curve: const FormSheetCurve());
    return AnimatedBuilder(
      animation: curved,
      child: builder(context),
      builder: (context, child) {
        final t = curved.value;
        return Center(
          child: Opacity(
            opacity: t,
            child: Transform.scale(
              scale: 1.2 - 0.2 * t,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: formSheetWidth,
                  maxHeight: formSheetMaxHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(formSheetMargin),
                  child: Material(child: child),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget buildModalBarrier() {
    final curved = CurvedAnimation(parent: animation!, curve: const FormSheetCurve());
    return FadeTransition(
      opacity: curved,
      child: ModalBarrier(
        color: barrierColor,
        dismissible: barrierDismissible,
        semanticsLabel: barrierLabel,
      ),
    );
  }
}
