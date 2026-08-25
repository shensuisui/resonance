/// 设置页 —— 主题切换 + 关于

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../providers/providers.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // 主题模式
          Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Text('外观', style: tt.titleSmall?.copyWith(color: cs.primary)),
          ),
          RadioListTile<ThemeMode>(
            value: ThemeMode.system,
            groupValue: themeMode,
            title: const Text('跟随系统'),
            onChanged: (v) => ref.read(themeModeProvider.notifier).setMode(v!),
          ),
          RadioListTile<ThemeMode>(
            value: ThemeMode.light,
            groupValue: themeMode,
            title: const Text('亮色'),
            onChanged: (v) => ref.read(themeModeProvider.notifier).setMode(v!),
          ),
          RadioListTile<ThemeMode>(
            value: ThemeMode.dark,
            groupValue: themeMode,
            title: const Text('暗色'),
            onChanged: (v) => ref.read(themeModeProvider.notifier).setMode(v!),
          ),
          const Divider(),
          // 关于
          Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Text('关于', style: tt.titleSmall?.copyWith(color: cs.primary)),
          ),
          const ListTile(
            leading: Icon(Icons.music_note_rounded),
            title: Text('FM 音乐'),
            subtitle: Text('全源音乐聚合播放器 v1.0.0'),
          ),
        ],
      ),
    );
  }
}
