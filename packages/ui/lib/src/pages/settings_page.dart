/// 设置页 —— 主题切换 + 本地扫描目录 + 关于

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_spacing.dart';
import '../providers/providers.dart';
import 'download_queue_page.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _scanDirController = TextEditingController();
  bool _scanDirLoaded = false;

  @override
  void dispose() {
    _scanDirController.dispose();
    super.dispose();
  }

  Future<void> _loadScanDir() async {
    if (_scanDirLoaded) return;
    final dir = await ref.read(scanNotifierProvider.notifier).getScanDir();
    _scanDirController.text = dir ?? '';
    _scanDirLoaded = true;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _loadScanDir();
    final themeMode = ref.watch(themeModeProvider);
    final scanState = ref.watch(scanNotifierProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // 外观
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
          // 本地音乐
          Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Text('本地音乐', style: tt.titleSmall?.copyWith(color: cs.primary)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
            child: TextField(
              controller: _scanDirController,
              decoration: const InputDecoration(
                labelText: '扫描目录',
                hintText: '如 /music 或 C:\\Music',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s16, vertical: AppSpacing.s8),
            child: Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text('保存路径'),
                  onPressed: () async {
                    await ref.read(scanNotifierProvider.notifier)
                        .setScanDir(_scanDirController.text.trim());
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('扫描目录已保存')),
                      );
                    }
                  },
                ),
                const SizedBox(width: AppSpacing.s12),
                ElevatedButton.icon(
                  icon: scanState.scanning
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search_rounded),
                  label: const Text('开始扫描'),
                  onPressed: scanState.scanning
                      ? null
                      : () async {
                          await ref.read(scanNotifierProvider.notifier)
                              .setScanDir(_scanDirController.text.trim());
                          await ref.read(scanNotifierProvider.notifier).scan();
                        },
                ),
              ],
            ),
          ),
          if (scanState.foundCount != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s16, vertical: AppSpacing.s4),
              child: Text(
                '扫描完成：新增 ${scanState.foundCount} 首',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          if (scanState.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s16, vertical: AppSpacing.s4),
              child: Text(
                '错误：${scanState.error}',
                style: tt.bodySmall?.copyWith(color: cs.error),
              ),
            ),
          const Divider(),
          // 下载
          Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Text('下载', style: tt.titleSmall?.copyWith(color: cs.primary)),
          ),
          ListTile(
            leading: const Icon(Icons.download_for_offline_rounded),
            title: const Text('下载管理'),
            subtitle: const Text('查看下载任务，取消或删除缓存'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const DownloadQueuePage(),
              ),
            ),
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
