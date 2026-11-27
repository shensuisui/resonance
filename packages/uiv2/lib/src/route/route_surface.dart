/// 路由页不透明底色：过渡中两页同绘时，页面必须自己铺底
library;

import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// 页面底色（跟随主题），和页面一起位移，不参与淡入
class RouteSurface extends StatelessWidget {
  /// 子内容
  final Widget child;

  /// 构造
  const RouteSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: UiV2Theme.of(context).bg, child: child);
}
