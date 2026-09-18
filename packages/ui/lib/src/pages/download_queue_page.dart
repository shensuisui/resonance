/// 下载队列管理页
///
/// 显示所有下载任务（下载中/已完成/失败/已取消），
/// 支持取消、删除缓存。
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../providers/providers.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radius.dart';
import '../widgets/empty_state.dart';

class DownloadQueuePage extends ConsumerWidget {
  const DownloadQueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(downloadManagerProvider);
    final tasksAsync = ref.watch(downloadTasksProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('下载管理')),
      body: tasksAsync.when(
        data: (tasks) {
          if (tasks.isEmpty) {
            // 空态统一走公共 EmptyState（插画圆底 + 主/副文案）
            return const EmptyState(
              icon: Icons.download_done_rounded,
              message: '暂无下载任务',
              hint: '在搜索或歌单中点下载按钮开始下载',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.s16),
            itemCount: tasks.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
            itemBuilder: (context, index) {
              final task = tasks[index];
              return _TaskCard(task: task, manager: manager);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState.error(
          message: '下载任务加载失败',
          detail: '$e',
          onRetry: () => ref.invalidate(downloadTasksProvider),
        ),
      ),
    );
  }

}

/// 单个下载任务卡片
class _TaskCard extends ConsumerWidget {
  final DownloadTask task;
  final DownloadManager manager;

  const _TaskCard({required this.task, required this.manager});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final songKey = task.songKey;

    // 统一卡片容器：固定圆角 s16，不随全局圆角设置变化（与 SongTile 同族）
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.s16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 主标题：优先展示歌名（来自本地歌曲表快照），失败时回退技术键
                  _SongTitle(songKey: songKey, fallback: _formatKey(songKey)),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    _formatKey(songKey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  _statusRow(cs, theme),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            _actionButton(ref, cs),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(ColorScheme cs, ThemeData theme) {
    final statusText = switch (task.status) {
      DownloadStatus.pending => '等待中',
      DownloadStatus.downloading => '下载中 ${(task.progress * 100).round()}%',
      DownloadStatus.completed => '已完成',
      DownloadStatus.cancelled => '已取消',
      DownloadStatus.failed => '失败: ${task.error ?? '未知错误'}',
    };
    final statusColor = switch (task.status) {
      DownloadStatus.completed => cs.primary,
      DownloadStatus.failed => cs.error,
      DownloadStatus.cancelled => cs.onSurfaceVariant,
      _ => cs.onSurfaceVariant,
    };

    return Row(
      children: [
        if (task.status == DownloadStatus.downloading)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.s8),
            child: SizedBox(
              width: AppSpacing.s16,
              height: AppSpacing.s16,
              child: CircularProgressIndicator(
                value: task.progress > 0 ? task.progress : null,
                strokeWidth: 2,
                color: cs.primary,
              ),
            ),
          ),
        Flexible(
          child: Text(
            statusText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: statusColor),
          ),
        ),
      ],
    );
  }

  Widget _actionButton(WidgetRef ref, ColorScheme cs) {
    switch (task.status) {
      case DownloadStatus.downloading:
      case DownloadStatus.pending:
        return IconButton(
          icon: Icon(Icons.cancel_rounded, color: cs.onSurfaceVariant),
          tooltip: '取消',
          onPressed: () => manager.cancel(task.songKey),
        );
      case DownloadStatus.completed:
        return IconButton(
          icon: Icon(Icons.delete_outline_rounded, color: cs.onSurfaceVariant),
          tooltip: '删除缓存',
          onPressed: () => manager.deleteCache(task.songKey),
        );
      case DownloadStatus.cancelled:
      case DownloadStatus.failed:
        // 重新下载：从源管理器按 songKey 恢复 Song 后再次下载
        return IconButton(
          icon: Icon(Icons.refresh_rounded, color: cs.onSurfaceVariant),
          tooltip: '重新下载',
          onPressed: () async {
            final parts = task.songKey.split(':');
            if (parts.length != 2) return;
            try {
              final sm = ref.read(sourceManagerProvider);
              final song = await sm.getSongDetail(parts[0], parts[1]);
              await manager.download(song);
            } catch (_) {
              // 源不可用则忽略（任务保留失败状态）
            }
          },
        );
    }
  }

    /// 格式化 songKey 为可读文本（技术键，作为副文案）
  String _formatKey(String songKey) {
    final parts = songKey.split(':');
    if (parts.length == 2) return '${parts[1]} (${parts[0]})';
    return songKey;
  }
}


/// 下载任务主标题：按 songKey 查本地歌曲快照，展示歌名 + 歌手
///
/// 下载任务的 songKey 形如 "sourceId:id"，直接展示是技术键、用户不可读；
/// 这里异步查本地歌曲表，查不到时回退传入的 [fallback] 文本。
class _SongTitle extends ConsumerWidget {
  final String songKey;
  final String fallback;

  const _SongTitle({required this.songKey, required this.fallback});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final parts = songKey.split(':');
    if (parts.length != 2) {
      return _titleText(theme, fallback, null);
    }
    final songAsync = ref.watch(_songByKeyProvider((sourceId: parts[0], id: parts[1])));
    return songAsync.maybeWhen(
      data: (song) => song == null
          ? _titleText(theme, fallback, null)
          : _titleText(theme, song.title, song.artist),
      orElse: () => _titleText(theme, fallback, null),
    );
  }

  /// 标题（歌名 + 可选歌手）
  Widget _titleText(ThemeData theme, String title, String? artist) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (artist != null && artist.isNotEmpty)
          Text(
            artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

/// 按 (sourceId, id) 查本地歌曲（下载任务标题用，带缓存）
final _songByKeyProvider =
    FutureProvider.family<Song?, ({String sourceId, String id})>((ref, key) async {
  final dao = ref.watch(songDaoProvider);
  return dao.getSong(key.id, key.sourceId);
});

