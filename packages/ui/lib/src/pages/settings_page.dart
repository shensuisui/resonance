/// 设置页 —— 主题切换 + 本地扫描目录 + 插件管理 + 下载 + 关于

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
    final dir = await ref.read(scanProvider.notifier).getScanDir();
    _scanDirController.text = dir ?? '';
    _scanDirLoaded = true;
    if (mounted) setState(() {});
  }

  /// 显示操作结果提示
  void _showMessage(String? message) {
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// 从 URL 添加插件对话框
  Future<void> _showAddUrlDialog() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从 URL 添加插件'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '插件地址',
            hintText: 'https://.../plugin.js 或 .json',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    final ok =
        await ref.read(pluginLibraryProvider.notifier).addFromUrl(url);
    _showMessage(ref.read(pluginLibraryProvider).message ??
        (ok ? '添加成功' : null));
  }

  @override
  Widget build(BuildContext context) {
    _loadScanDir();
    final themeMode = ref.watch(themeModeProvider);
    final scanState = ref.watch(scanProvider);
    final pluginState = ref.watch(pluginLibraryProvider);
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
                    await ref.read(scanProvider.notifier)
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
                          await ref.read(scanProvider.notifier)
                              .setScanDir(_scanDirController.text.trim());
                          await ref.read(scanProvider.notifier).scan();
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
          // 插件
          Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Text('插件', style: tt.titleSmall?.copyWith(color: cs.primary)),
          ),
          // 已加载插件列表
          for (final plugin in pluginState.plugins)
            ListTile(
              leading: const Icon(Icons.extension_rounded),
              title: Text(plugin.sourceInfo.name, maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              subtitle: Text(plugin.sourceInfo.id, maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          if (pluginState.plugins.isEmpty && !pluginState.loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
              child: Text(
                '暂无插件，可从下方导入或加载默认源',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.upload_file_rounded),
            title: const Text('导入插件文件'),
            subtitle: const Text('支持 .js / .json（落雪、MusicFree）'),
            onTap: () async {
              await ref.read(pluginLibraryProvider.notifier).importFromFile();
              _showMessage(ref.read(pluginLibraryProvider).message);
            },
          ),
          ListTile(
            leading: const Icon(Icons.link_rounded),
            title: const Text('从 URL 添加插件'),
            onTap: _showAddUrlDialog,
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download_rounded),
            title: const Text('加载默认插件源'),
            subtitle: const Text('落雪音乐 + MusicFree 官方地址'),
            onTap: () async {
              final count = await ref
                  .read(pluginLibraryProvider.notifier)
                  .loadDefaults();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(count > 0 ? '已加载 $count 个默认插件' : '默认插件源加载失败')),
              );
            },
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
