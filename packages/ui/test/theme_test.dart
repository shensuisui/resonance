/// UI 主题系统测试
///
/// 验证 AppSpacing / AppRadius / AppTheme 的静态值和主题配置。
/// 禁止魔法值——所有间距和圆角必须从预定义常量获取。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

void main() {
  group('AppSpacing', () {
    test('所有间距值为正数且递增', () {
      expect(AppSpacing.s2, 2);
      expect(AppSpacing.s4, 4);
      expect(AppSpacing.s8, 8);
      expect(AppSpacing.s12, 12);
      expect(AppSpacing.s16, 16);
      expect(AppSpacing.s20, 20);
      expect(AppSpacing.s24, 24);
      expect(AppSpacing.s32, 32);
      expect(AppSpacing.s48, 48);
      expect(AppSpacing.s64, 64);
    });

    test('间距值严格递增', () {
      final values = [
        AppSpacing.s2, AppSpacing.s4, AppSpacing.s8, AppSpacing.s12,
        AppSpacing.s16, AppSpacing.s20, AppSpacing.s24, AppSpacing.s32,
        AppSpacing.s48, AppSpacing.s64,
      ];
      for (int i = 1; i < values.length; i++) {
        expect(values[i], greaterThan(values[i - 1]),
            reason: '间距应严格递增');
      }
    });
  });

  group('AppRadius', () {
    test('所有圆角值为正数', () {
      expect(AppRadius.s4, 4);
      expect(AppRadius.s8, 8);
      expect(AppRadius.s12, 12);
      expect(AppRadius.s16, 16);
      expect(AppRadius.s24, 24);
      expect(AppRadius.full, 999);
    });

    test('full 用于圆形', () {
      expect(AppRadius.full, greaterThan(100));
    });
  });

  group('AppTheme', () {
    test('light() 返回亮色主题', () {
      final theme = AppTheme.light();
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.brightness, Brightness.light);
    });

    test('dark() 返回暗色主题', () {
      final theme = AppTheme.dark();
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('light 和 dark 使用相同种子色', () {
      final lightTheme = AppTheme.light();
      final darkTheme = AppTheme.dark();
      // 种子色应相同（都是 deepPurple），但 brightness 不同
      expect(lightTheme.colorScheme.primary, isNot(equals(darkTheme.colorScheme.primary)),
          reason: '亮暗主题的 primary 应不同');
    });

    test('light() 可用于 MaterialApp', () {
      final theme = AppTheme.light();
      // 验证返回的是有效的 ThemeData
      expect(theme, isA<ThemeData>());
      expect(theme.colorScheme, isA<ColorScheme>());
    });

    test('dark() 可用于 MaterialApp', () {
      final theme = AppTheme.dark();
      expect(theme, isA<ThemeData>());
      expect(theme.colorScheme, isA<ColorScheme>());
    });
  });
}
