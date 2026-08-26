/// 源管理页 —— 源列表 + 类型/来源归属 + 启用/禁用开关
///
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。

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
    // 来源归属：sourceId → 订阅 url（远程源显示来源）
    final originMap = ref.watch(subscriptionLibraryProvider).sourceOrigin;
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
              final origin = originMap[info.id];

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
                  child: Icon(_typeIcon(info.type), color: cs.onSurfaceVariant),
                ),
                title: Text(info.name, style: tt.bodyLarge),
                subtitle: Text(
                  _subtitle(info, origin),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
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

  /// 类型图标
  IconData _typeIcon(SourceType type) => switch (type) {
        SourceType.local => Icons.folder_rounded,
        SourceType.rule => Icons.description_rounded,
        SourceType.plugin => Icons.extension_rounded,
      };

  /// 类型标签
  String _typeLabel(SourceType type) => switch (type) {
        SourceType.local => '本地',
        SourceType.rule => '规则',
        SourceType.plugin => '插件',
      };

  /// 副标题：id · 类型[ · 来源]
  String _subtitle(SourceInfo info, String? origin) {
    final parts = [info.id, _typeLabel(info.type)];
    if (origin != null && origin.isNotEmpty) {
      final host = Uri.tryParse(origin)?.host;
      parts.add('来自 ${host?.isNotEmpty == true ? host : origin}');
    }
    return parts.join(' · ');
  }
}
