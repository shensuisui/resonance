/// 应用主题 —— 可切换亮/暗模式，种子色与全局圆角可配置
///
/// 所有颜色通过 [Theme.of] 获取，禁止硬编码颜色值。
/// 主题模式持久化在 settings 表（key = theme_mode）。
/// 种子色持久化在 settings 表（key = seed_color，'#RRGGBB' 文本）。
/// 全局圆角持久化在 settings 表（key = corner_radius，整数文本）。
library;

import 'package:flutter/material.dart';

/// 主题种子色预设项（配表驱动，禁止散落硬编码色值）
class SeedColorPreset {
  final String name;
  final Color color;

  const SeedColorPreset(this.name, this.color);
}

/// 种子色预设清单（设置页「主题色」选择用）
const List<SeedColorPreset> kSeedColorPresets = [
  SeedColorPreset('深紫', Color(0xFF673AB7)),
  SeedColorPreset('靛蓝', Color(0xFF3F51B5)),
  SeedColorPreset('天蓝', Color(0xFF1E88E5)),
  SeedColorPreset('青', Color(0xFF00897B)),
  SeedColorPreset('绿', Color(0xFF43A047)),
  SeedColorPreset('橙', Color(0xFFFB8C00)),
  SeedColorPreset('粉', Color(0xFFE91E63)),
  SeedColorPreset('棕', Color(0xFF8D6E63)),
];

/// 默认种子色（深紫，settings 无记录时的初始值）
const Color kDefaultSeedColor = Color(0xFF673AB7);

/// 全局圆角默认值（settings 无记录时的初始值）
const int kDefaultCornerRadius = 12;

/// 全局圆角允许范围
const int kCornerRadiusMin = 0;
const int kCornerRadiusMax = 32;

/// Color → '#RRGGBB'（settings key-value 存储用，忽略 alpha）
String colorToHex(Color c) {
  final v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// '#RRGGBB' → Color；非法输入回退 [kDefaultSeedColor]
Color hexToColor(String hex) {
  final h = hex.replaceFirst('#', '');
  final v = int.tryParse(h, radix: 16);
  if (v == null) return kDefaultSeedColor;
  return Color(0xFF000000 | (v & 0xFFFFFF));
}

class AppTheme {
  AppTheme._();

  /// 亮色主题；[seedColor] 主题种子色，[cornerRadius] 全局圆角（作用于
  /// 卡片/对话框/底部弹层等容器组件，统一注入避免逐组件改）。
  static ThemeData light({
    Color seedColor = kDefaultSeedColor,
    int cornerRadius = kDefaultCornerRadius,
  }) =>
      _build(Brightness.light, seedColor, cornerRadius);

  /// 暗色主题（参数同 [light]）
  static ThemeData dark({
    Color seedColor = kDefaultSeedColor,
    int cornerRadius = kDefaultCornerRadius,
  }) =>
      _build(Brightness.dark, seedColor, cornerRadius);

  static ThemeData _build(
      Brightness brightness, Color seedColor, int cornerRadius) {
    final radius = BorderRadius.circular(cornerRadius.toDouble());
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      ),
      // 全局圆角统一注入容器组件（保持 M3 组件默认交互语义）
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    );
  }
}
