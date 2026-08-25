/// 应用主题 —— 可切换亮/暗模式
///
/// 所有颜色通过 [Theme.of] 获取，禁止硬编码颜色值。
/// 主题模式持久化在 settings 表（key = theme_mode）。

import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  /// 种子色（可后续改为用户可配置）
  static const Color _seedColor = Colors.deepPurple;

  /// 亮色主题
  static ThemeData light() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.light,
        ),
      );

  /// 暗色主题
  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
      );
}
