/// 大屏：200ms 原地淡入；被覆盖页完全不动
library;

import 'package:flutter/material.dart';

import 'drag_back.dart';

/// 淡入路由（桌面/平板）
class FadePageRoute<T> extends PageRoute<T> with DragBackRouteMixin<T> {
  /// 页面构造器
  final WidgetBuilder builder;

  /// 构造
  FadePageRoute({required this.builder, super.settings});

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        child: builder(context),
      );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 只有鼠标拖拽返回激活时才改成横向滑动；平时线性淡入，被覆盖页不参与
    return dragBackDetector(
      ValueListenableBuilder<bool>(
        valueListenable: isDragBackActive,
        builder: (context, active, _) => active
            ? dragBackSlide(animation, child)
            : FadeTransition(opacity: animation, child: child),
      ),
    );
  }
}
