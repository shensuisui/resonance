/// 主题装配 —— 把设计令牌与 Material 主题接到一起。
///
/// 原型靠 [data-theme] 切明暗；这里由 MaterialApp 的 theme/darkTheme 决定，
/// 再用 [UiV2Scope] 把同一套令牌注入 Widget 树，供组件用 [UiV2Theme.of] 取值。
library;

import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

/// 回响主题工厂。
abstract final class UiV2DesignTheme {
  /// 暗色主题（原型默认）。
  static ThemeData dark() => build(Brightness.dark);

  /// 亮色主题。
  static ThemeData light() => build(Brightness.light);

  /// 按亮度构建 Material 主题；组件颜色仍以 [UiV2Tokens] 为准。
  static ThemeData build(Brightness brightness) {
    final t = UiV2Tokens.of(brightness);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: t.bg,
      canvasColor: t.bg,
      fontFamily: kFontBody,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: t.accent,
        onPrimary: t.accentInk,
        secondary: t.accent,
        onSecondary: t.accentInk,
        error: t.danger,
        onError: t.accentInk,
        surface: t.bg,
        onSurface: t.text,
        surfaceContainerHighest: t.surface3,
        outline: t.lineStrong,
      ),
      textTheme: TextTheme(
        bodyMedium: UiV2Text.body.copyWith(color: t.text),
        titleMedium: UiV2Text.trackTitle.copyWith(color: t.text),
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      dividerColor: t.line,
    );
  }
}

/// 令牌作用域包装 —— 在 MaterialApp 的 builder 里包一层，
/// 让全部子组件拿到与当前主题一致的 [UiV2Tokens]。
class UiV2Scope extends StatelessWidget {
  /// 子组件
  final Widget child;

  /// 构造作用域
  const UiV2Scope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return UiV2Theme(
      tokens: UiV2Tokens.of(brightness),
      child: IconTheme.merge(
        data: IconThemeData(color: UiV2Tokens.of(brightness).textDim, size: 22),
        child: DefaultTextStyle.merge(
          style: UiV2Text.body.copyWith(color: UiV2Tokens.of(brightness).text),
          child: child,
        ),
      ),
    );
  }
}
