/// go_router 桥：FadePage
library;

import 'package:flutter/material.dart';

import 'fade_page_route.dart';

/// 大屏二级页
class FadePage<T> extends Page<T> {
  /// 页面内容
  final Widget child;

  /// 构造
  const FadePage({required this.child, super.key, super.name});

  @override
  Route<T> createRoute(BuildContext context) =>
      FadePageRoute<T>(settings: this, builder: (_) => child);
}
