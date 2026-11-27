/// go_router 桥：CardPage -> CardPageRoute
library;

import 'package:flutter/material.dart';

import 'card_route.dart';
import 'drag_back.dart';

/// 移动端二级页：卡片推入 + 全屏拖拽返回
class CardPage<T> extends Page<T> {
  /// 页面内容
  final Widget child;

  /// 构造
  const CardPage({required this.child, super.key, super.name});

  @override
  Route<T> createRoute(BuildContext context) => CardPageRoute<T>(
        settings: this,
        builder: (_) => child,
      );
}

/// 卡片路由
class CardPageRoute<T> extends PageRoute<T>
    with DragBackRouteMixin<T>, CardRouteMixin<T> {
  /// 页面构造器
  final WidgetBuilder builder;

  /// 构造
  CardPageRoute({required this.builder, super.settings});

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get opaque => true;

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

  // HeroController 会把首帧页面 offstage 并把动画钉在 completed，禁止
  @override
  set offstage(bool value) {}
}
