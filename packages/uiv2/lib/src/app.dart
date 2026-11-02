/// 应用根组件 —— 把设计主题、令牌作用域与路由组装起来。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';
import 'design/theme.dart';
import 'providers/providers.dart';

// 路由与根 Navigator key 都在 app_router.dart（避免 app → app_router → app 的循环导入）
export 'app_router.dart' show uiV2NavigatorKey, uiV2DismissOverlays;

/// 回响（uiv2）应用根组件
class UiV2App extends ConsumerWidget {
  /// 应用标题（任务栏 / 窗口标题）
  final String title;

  /// 构造应用
  const UiV2App({super.key, this.title = '回响 Resonance'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    // 路由由 go_router 持有：一级页保活（StatefulShellRoute）、二级页带转场，
    // 业务代码仍然只调 navProvider.go/back（门面，见 router.dart）。
    return MaterialApp.router(
      routerConfig: ref.watch(appRouterProvider),
      title: title,
      debugShowCheckedModeBanner: false,
      theme: UiV2DesignTheme.light(),
      darkTheme: UiV2DesignTheme.dark(),
      themeMode: mode,
      builder: (context, child) =>
          UiV2Scope(child: child ?? const SizedBox.shrink()),
    );
  }
}
