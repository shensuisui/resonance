/// 大屏侧边 sheet：300/200ms 右侧平移，宽度 0.4 视口夹 360–560
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 进入/退出时长
const Duration sideSheetEnter = Duration(milliseconds: 300);
const Duration sideSheetExit = Duration(milliseconds: 200);

/// 宽度约束
const double sideSheetMinWidth = 360.0;
const double sideSheetMaxWidth = 560.0;
const double sideSheetWidthFactor = 0.4;

/// 宽度公式（纯函数，便于单测）
double sideSheetWidthFor(double viewWidth) =>
    (viewWidth * sideSheetWidthFactor).clamp(sideSheetMinWidth, sideSheetMaxWidth);

/// 侧边 sheet 路由
class SideSheetRoute<T> extends PopupRoute<T> {
  /// 内容
  final WidgetBuilder builder;

  /// 遮罩颜色
  final Color barrierColor;

  /// 构造
  SideSheetRoute({
    required this.builder,
    this.barrierColor = const Color(0x66000000),
    super.settings,
  });

  @override
  Duration get transitionDuration => sideSheetEnter;

  @override
  Duration get reverseTransitionDuration => sideSheetExit;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => '关闭';

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      _SideSheetLayout(animation: animation, child: builder(context));

  @override
  Widget buildModalBarrier() => FadeTransition(
        opacity: animation!,
        child: ModalBarrier(
          color: barrierColor,
          dismissible: barrierDismissible,
          semanticsLabel: barrierLabel,
        ),
      );
}

class _SideSheetLayout extends SingleChildRenderObjectWidget {
  final Animation<double> animation;

  const _SideSheetLayout({required this.animation, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSideSheetLayout(animation: animation);

  @override
  void updateRenderObject(BuildContext context, _RenderSideSheetLayout renderObject) {
    renderObject.animation = animation;
  }
}

class _RenderSideSheetLayout extends RenderShiftedBox {
  _RenderSideSheetLayout({required Animation<double> animation})
      : _animation = animation,
        super(null) {
    _animation.addListener(_onTick);
  }

  Animation<double> _animation;

  set animation(Animation<double> value) {
    if (identical(value, _animation)) return;
    _animation.removeListener(_onTick);
    _animation = value..addListener(_onTick);
    markNeedsLayout();
  }

  void _onTick() => markNeedsLayout();

  @override
  void performLayout() {
    final t = _animation.value;
    final width = sideSheetWidthFor(constraints.maxWidth);
    final childConstraints = BoxConstraints.tightFor(
      width: width,
      height: constraints.maxHeight,
    );
    final child = this.child!;
    child.layout(childConstraints, parentUsesSize: true);
    size = constraints.biggest;
    (child.parentData! as BoxParentData).offset = Offset(
      size.width - child.size.width * t,
      0,
    );
  }

  @override
  void dispose() {
    _animation.removeListener(_onTick);
    super.dispose();
  }
}
