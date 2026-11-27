/// go_router 桥：首屏页不播转场（时长 0）
library;

import 'package:flutter/material.dart';

/// 一级页（每个 tab 的首屏）
class RootPage<T> extends Page<T> {
  /// 页面内容
  final Widget child;

  /// 构造
  const RootPage({required this.child, super.key, super.name});

  @override
  Route<T> createRoute(BuildContext context) =>
      RootPageRoute<T>(settings: this, builder: (_) => child);
}

/// 零时长根路由
class RootPageRoute<T> extends PageRoute<T> {
  /// 页面构造器
  final WidgetBuilder builder;

  /// 构造
  RootPageRoute({required this.builder, super.settings});

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

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

  // 首屏自身不参与推入，但作为被覆盖页仍要接收 secondaryAnimation（左移 30%）
  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) => true;

  @override
  set offstage(bool value) {}
}
