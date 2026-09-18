/// 源执行日志页 —— 展示各音乐源的操作日志（搜索/播放URL/歌词等）
///
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radius.dart';
import '../providers/providers.dart';
import '../widgets/empty_state.dart';

class SourceLogPage extends ConsumerWidget {
  const SourceLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sourceLogProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('运行日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: '清空日志',
            onPressed: () =>
                ref.read(sourceLogProvider.notifier).clear(),
          ),
        ],
      ),
      body: state.entries.isEmpty
          ? const EmptyState(
              icon: Icons.article_outlined,
              message: '暂无日志',
              hint: '搜索、播放等操作会记录各源执行情况',
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
              itemCount: state.entries.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, indent: AppSpacing.s16),
              itemBuilder: (context, index) {
                final entry = state.entries[index];
                return _LogTile(entry: entry);
              },
            ),
    );
  }
}

/// 单条日志条目
class _LogTile extends StatelessWidget {
  final SourceLogEntry entry;

  const _LogTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // 级别颜色：错误红、警告橙、信息默认
    final levelColor = switch (entry.level) {
      SourceLogLevel.error => cs.error,
      SourceLogLevel.warn => Colors.orange.shade700,
      SourceLogLevel.info => cs.primary,
    };
    // 级别图标
    final IconData levelIcon = switch (entry.level) {
      SourceLogLevel.error => Icons.error_outline_rounded,
      SourceLogLevel.warn => Icons.warning_amber_rounded,
      SourceLogLevel.info => Icons.info_outline_rounded,
    };

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s4,
      ),
      dense: true,
      leading: Icon(levelIcon, size: 20, color: levelColor),
      title: Row(
        children: [
          Text(
            entry.timeText,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: AppSpacing.s8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: 2),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.s4),
            ),
            child: Text(
              entry.sourceId,
              style: tt.bodySmall?.copyWith(
                color: levelColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Text(
              '[${entry.action}]',
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
      subtitle: Text(
        entry.detail,
        style: tt.bodyMedium,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}