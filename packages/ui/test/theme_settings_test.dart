/// 主题外观参数测试 —— 种子色预设 / hex 工具 / AppTheme 可配置 / Notifier 持久化
///
/// 对应 lib/src/theme/app_theme.dart 与 providers 中的
/// SeedColorNotifier、CornerRadiusNotifier。
/// 模拟数据来源：内存 SettingsDao（与真实 sqflite key-value 语义一致）。
/// Notifier 的异步 _load 用短延时等待完成。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

/// 内存 SettingsDao（key-value，语义同 SqfliteSettingsDao）
class MemorySettingsDao implements SettingsDao {
  final Map<String, String> _store = {};

  @override
  Future<String?> get(String key) async => _store[key];

  @override
  Future<void> set(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<Map<String, String>> getAll() async => Map.of(_store);

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }
}

/// 假 DatabaseProvider：仅实现 settingsDao，其余 DAO 不触达
class FakeDatabaseProvider implements DatabaseProvider {
  final settings = MemorySettingsDao();

  @override
  Future<void> initialize() async {}

  @override
  SongDao get songDao => throw UnimplementedError();

  @override
  PlaylistDao get playlistDao => throw UnimplementedError();

  @override
  RecentPlaysDao get recentPlaysDao => throw UnimplementedError();

  @override
  PlayProgressDao get playProgressDao => throw UnimplementedError();

  @override
  FavoritesDao get favoritesDao => throw UnimplementedError();

  @override
  SettingsDao get settingsDao => settings;
}

void main() {
  group('种子色预设', () {
    test('预设清单 8 项且含默认深紫', () {
      expect(kSeedColorPresets.length, 8);
      expect(kSeedColorPresets.first.name, '深紫');
      expect(kSeedColorPresets.first.color, kDefaultSeedColor);
    });

    test('预设色值合法（非透明）', () {
      for (final p in kSeedColorPresets) {
        expect(p.color.a, 1.0, reason: '${p.name} 应为不透明色');
      }
    });
  });

  group('hex 工具', () {
    test('colorToHex 输出 #RRGGBB', () {
      expect(colorToHex(const Color(0xFF673AB7)), '#673AB7');
      expect(colorToHex(const Color(0xFF000000)), '#000000');
      expect(colorToHex(const Color(0xFFFFFFFF)), '#FFFFFF');
    });

    test('hexToColor 解析合法输入', () {
      expect(hexToColor('#3F51B5'), const Color(0xFF3F51B5));
      expect(hexToColor('43A047'), const Color(0xFF43A047));
    });

    test('hexToColor 非法输入回退默认深紫', () {
      expect(hexToColor('oops'), kDefaultSeedColor);
      expect(hexToColor(''), kDefaultSeedColor);
    });

    test('往返一致', () {
      for (final p in kSeedColorPresets) {
        expect(hexToColor(colorToHex(p.color)), p.color);
      }
    });
  });

  group('AppTheme 可配置', () {
    test('light() 默认种子色为深紫', () {
      final theme = AppTheme.light();
      // 与 ColorScheme.fromSeed(深紫) 直接生成的 primary 一致
      final expected =
          ColorScheme.fromSeed(seedColor: kDefaultSeedColor).primary;
      expect(theme.colorScheme.primary, expected);
    });

    test('指定种子色改变 colorScheme', () {
      final theme = AppTheme.light(seedColor: const Color(0xFF1E88E5));
      final defaultTheme = AppTheme.light();
      expect(theme.colorScheme.primary, isNot(defaultTheme.colorScheme.primary));
    });

    test('light 与 dark 使用相同种子色参数', () {
      final seed = const Color(0xFF43A047);
      final lightTheme = AppTheme.light(seedColor: seed);
      final darkTheme = AppTheme.dark(seedColor: seed);
      final expected = ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
      ).primary;
      expect(darkTheme.colorScheme.primary, expected);
      expect(lightTheme.colorScheme.primary, isNot(darkTheme.colorScheme.primary));
    });

    test('默认全局圆角 12 注入卡片', () {
      final theme = AppTheme.light();
      final shape = theme.cardTheme.shape! as RoundedRectangleBorder;
      final radius = shape.borderRadius as BorderRadius;
      expect(radius.topLeft.x, 12);
    });

    test('指定圆角注入卡片/对话框/底部弹层', () {
      final theme = AppTheme.light(cornerRadius: 20);
      for (final shape in [
        theme.cardTheme.shape,
        theme.dialogTheme.shape,
        theme.bottomSheetTheme.shape,
      ]) {
        final rounded = shape! as RoundedRectangleBorder;
        expect((rounded.borderRadius as BorderRadius).topLeft.x, 20);
      }
    });
  });

  group('SeedColorNotifier', () {
    test('默认种子色为深紫', () {
      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWith((ref) => FakeDatabaseProvider()),
      ]);
      addTearDown(container.dispose);
      expect(container.read(seedColorProvider), kDefaultSeedColor);
    });

    test('setSeedColor 持久化为 hex', () async {
      final db = FakeDatabaseProvider();
      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
      ]);
      addTearDown(container.dispose);
      await container
          .read(seedColorProvider.notifier)
          .setSeedColor(const Color(0xFF3F51B5));
      expect(container.read(seedColorProvider), const Color(0xFF3F51B5));
      expect(await db.settingsDao.get('seed_color'), '#3F51B5');
    });

    test('从 settings 恢复种子色', () async {
      final db = FakeDatabaseProvider();
      await db.settingsDao.set('seed_color', '#FB8C00');
      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
      ]);
      addTearDown(container.dispose);
      // 先 read 触发 build（异步 _load 启动），再等待其完成
      container.read(seedColorProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(seedColorProvider), const Color(0xFFFB8C00));
    });
  });

  group('CornerRadiusNotifier', () {
    test('默认全局圆角 12', () {
      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWith((ref) => FakeDatabaseProvider()),
      ]);
      addTearDown(container.dispose);
      expect(container.read(cornerRadiusProvider), kDefaultCornerRadius);
    });

    test('setCornerRadius 持久化并夹取边界', () async {
      final db = FakeDatabaseProvider();
      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
      ]);
      addTearDown(container.dispose);
      await container
          .read(cornerRadiusProvider.notifier)
          .setCornerRadius(100); // 超上限夹取
      expect(container.read(cornerRadiusProvider), kCornerRadiusMax);
      expect(await db.settingsDao.get('corner_radius'), '${kCornerRadiusMax}');
      await container
          .read(cornerRadiusProvider.notifier)
          .setCornerRadius(-5); // 低于下限夹取
      expect(container.read(cornerRadiusProvider), kCornerRadiusMin);
    });

    test('从 settings 恢复圆角', () async {
      final db = FakeDatabaseProvider();
      await db.settingsDao.set('corner_radius', '20');
      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWith((ref) => db),
      ]);
      addTearDown(container.dispose);
      // 先 read 触发 build（异步 _load 启动），再等待其完成
      container.read(cornerRadiusProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(cornerRadiusProvider), 20);
    });
  });
}
