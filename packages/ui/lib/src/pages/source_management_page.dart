/// 源管理页 —— 源列表 + 启用/禁用开关

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../theme/app_spacing.dart';
import '../providers/providers.dart';

class SourceManagementPage extends ConsumerWidget {
  const SourceManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourcesAsync = ref.watch(sourceListProvider);
    final enabledMap = ref.watch(sourceEnabledProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('音乐源')),
      body: sourcesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (sources) {
          if (sources.isEmpty) {
            return Center(
              child: Text('暂无已注册源', style: tt.bodyLarge?.copyWith(
                color: cs.onSurfaceVariant,
              )),
            );
          }
          return ListView.builder(
            itemCount: sources.length,
            itemBuilder: (context, index) {
              final source = sources[index];
              final info = source.sourceInfo;
              final isEnabled = enabledMap[info.id] ?? false;

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s16,
                  vertical: AppSpacing.s4,
                ),
                leading: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(Icons.cloud_rounded, color: cs.onSurfaceVariant),
                ),
                title: Text(info.name, style: tt.bodyLarge),
                subtitle: Text(info.id, style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                )),
                trailing: Switch(
                  value: isEnabled,
                  onChanged: (v) {
                    ref.read(sourceEnabledProvider.notifier).toggle(info.id, v);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
