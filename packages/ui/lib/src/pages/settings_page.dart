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

  /// 添加订阅对话框（别名 + URL + 手动指定类型）
  Future<(String, SubscriptionType, String)?> _showAddSubscriptionDialog() async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    var type = SubscriptionType.singleRule;
    return showDialog<(String, SubscriptionType, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加订阅'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '别名（可选）',
                  hintText: '如：枫叶音乐、My Music',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              TextField(
                controller: urlController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '订阅地址',
                  hintText: 'https://...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              DropdownButtonFormField<SubscriptionType>(
                initialValue: type,
                decoration: const InputDecoration(
                  labelText: '类型',
                  border: OutlineInputBorder(),
                ),
                items: SubscriptionType.values
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t.label),
                        ))
                    .toList(),
                onChanged: (v) => setDialogState(() => type = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                  context,
                  (urlController.text.trim(), type, nameController.text.trim())),
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  /// 格式化上次检查时间
  String _formatTime(DateTime? time) {
    if (time == null) return '从未检查';
    final m = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$m-$day $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    _loadScanDir();
    final themeMode = ref.watch(themeModeProvider);
    final scanState = ref.watch(scanProvider);
    final pluginState = ref.watch(pluginLibraryProvider);
    final subState = ref.watch(subscriptionLibraryProvider);
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
          // 订阅
          Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Text('订阅', style: tt.titleSmall?.copyWith(color: cs.primary)),
          ),
          // 订阅列表
          for (final sub in subState.subscriptions)
            ListTile(
              leading: Icon(sub.type == SubscriptionType.mfGroup ||
                      sub.type == SubscriptionType.singlePlugin
                  ? Icons.extension_rounded
                  : Icons.description_rounded),
              title: Text(sub.name ?? sub.type.label,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${sub.type.label} · ${sub.url}\n${subState.sourceCounts[sub.url] ?? 0} 源 · 上次检查 ${_formatTime(sub.lastCheckedAt)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: '检查更新',
                    onPressed: () async {
                      await ref
                          .read(subscriptionLibraryProvider.notifier)
                          .updateSubscription(sub.url);
                      _showMessage(
                          ref.read(subscriptionLibraryProvider).message);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    tooltip: '删除订阅',
                    onPressed: () async {
                      await ref
                          .read(subscriptionLibraryProvider.notifier)
                          .removeSubscription(sub.url);
                      _showMessage(
                          ref.read(subscriptionLibraryProvider).message);
                    },
                  ),
                ],
              ),
            ),
          if (subState.subscriptions.isEmpty && !subState.loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
              child: Text(
                '暂无订阅，可添加远程规则或插件订阅',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.add_circle_outline_rounded),
            title: const Text('添加订阅'),
            subtitle: const Text('规则 / 规则组 / MusicFree 组 / 单插件'),
            onTap: () async {
              final result = await _showAddSubscriptionDialog();
              if (result == null) return;
              final (url, type, name) = result;
              if (url.isEmpty) return;
              await ref
                  .read(subscriptionLibraryProvider.notifier)
                  .addSubscription(url, type, name: name);
              _showMessage(ref.read(subscriptionLibraryProvider).message);
            },
          ),
          ListTile(
            leading: const Icon(Icons.sync_rounded),
            title: const Text('全部检查更新'),
            onTap: () async {
              final (ok, fail) = await ref
                  .read(subscriptionLibraryProvider.notifier)
                  .updateAll();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('更新完成：成功 $ok，失败 $fail')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download_rounded),
            title: const Text('添加默认订阅'),
            subtitle: const Text('落雪音乐 + MusicFree 官方地址'),
            onTap: () async {
              final count = await ref
                  .read(subscriptionLibraryProvider.notifier)
                  .addDefaultSubscriptions();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(count > 0 ? '已登记 $count 个默认订阅' : '默认订阅已存在或登记失败')),
              );
            },
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
