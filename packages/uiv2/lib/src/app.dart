/// 应用根组件 —— 把设计主题、令牌作用域与外壳组装起来。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design/theme.dart';
import 'pages/app_shell.dart';
import 'providers/providers.dart';

/// 全局 Navigator key
///
/// 唯一用途：发版前集成检查的 recover 需要「关掉所有模态浮层」（sheet / dialog）。
/// 业务代码不依赖它；debug-only 扩展通过 [uiV2DismissOverlays] 调到根路由。
final GlobalKey<NavigatorState> uiV2NavigatorKey = GlobalKey<NavigatorState>();

/// 关掉所有模态浮层，回到根路由；返回是否执行成功
bool uiV2DismissOverlays() {
  final navigator = uiV2NavigatorKey.currentState;
  if (navigator == null) return false;
  navigator.popUntil((route) => route.isFirst);
  return true;
}

/// 回响（uiv2）应用根组件
class UiV2App extends ConsumerWidget {
  /// 应用标题（任务栏 / 窗口标题）
  final String title;

  /// 构造应用
  const UiV2App({super.key, this.title = '回响 Resonance'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp(
      navigatorKey: uiV2NavigatorKey,
      title: title,
      debugShowCheckedModeBanner: false,
      theme: UiV2DesignTheme.light(),
      darkTheme: UiV2DesignTheme.dark(),
      themeMode: mode,
      builder: (context, child) => UiV2Scope(child: child ?? const SizedBox.shrink()),
      home: const UiV2AppShell(),
    );
  }
}
