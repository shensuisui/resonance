/// 播放队列 Sheet —— 拖拽排序 + 滑动删除 + 撤销（对标 PixelPlayer QueueBottomSheet）
///
/// 底部弹层展示当前播放队列：
/// - 长按拖拽排序（ReorderableListView），写回 player 队列并同步 provider
/// - 左滑删除（Dismissible），SnackBar 提供 2 秒内撤销
/// - 点击队列项跳转播放
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../providers/providers.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radius.dart';

/// 弹出播放队列 Sheet
Future<void> showQueueSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const QueueSheet(),
  );
}

class QueueSheet extends ConsumerWidget {
  const QueueSheet({super.key});

  /// 应用新队列：写回播放器并同步 UI provider
  void _applyQueue(WidgetRef ref, List<Song> queue) {
    ref.read(playerProvider).setQueue(queue);
    ref.read(playQueueProvider.notifier).setQueue(queue);
  }

  /// 移除指定项并给出撤销入口
  void _removeWithUndo(BuildContext context, WidgetRef ref, int index,
      List<Song> queue) {
    final removed = queue[index];
    final original = List<Song>.from(queue);
    final newQueue = List<Song>.from(queue)..removeAt(index);
    _applyQueue(ref, newQueue);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已移除 ${removed.title}'),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => _applyQueue(ref, original),
        ),
      ),
    );
  }

  /// 拖拽排序回调（newIndex 越位修正）
  void _onReorder(WidgetRef ref, List<Song> queue, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final newQueue = List<Song>.from(queue);
    final moved = newQueue.removeAt(oldIndex);
    newQueue.insert(newIndex, moved);
    _applyQueue(ref, newQueue);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final queue = ref.watch(playQueueProvider);
    final current = ref.watch(currentSongProvider);

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s16, AppSpacing.s4, AppSpacing.s16, AppSpacing.s8),
              child: Text('播放队列 (${queue.length})',
                  style: tt.titleMedium),
            ),
            const Divider(height: 1),
            Expanded(
              child: queue.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.queue_music_rounded,
                              size: 48, color: cs.onSurfaceVariant),
                          const SizedBox(height: AppSpacing.s12),
                          Text('队列为空',
                              style: tt.bodyMedium
                                  ?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    )
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      onReorder: (oldI, newI) =>
                          _onReorder(ref, queue, oldI, newI),
                      itemCount: queue.length,
                      itemBuilder: (context, index) {
                        final song = queue[index];
                        final isCurrent = current != null &&
                            current.sourceId == song.sourceId &&
                            current.id == song.id;
                        return Dismissible(
                          // 用歌曲全局唯一键：删除后新项不继承 dismissed 状态
                          key: ValueKey('queue_${song.globalKey}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: cs.errorContainer,
                            alignment: Alignment.centerRight,
                            padding:
                                const EdgeInsets.only(right: AppSpacing.s24),
                            child: Icon(Icons.remove_circle_outline_rounded,
                                color: cs.onErrorContainer),
                          ),
                          onDismissed: (_) =>
                              _removeWithUndo(context, ref, index, queue),
                          child: Container(
                            // 与 SongTile 同款卡片容器：当前播放用 primaryContainer
                            margin: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s12,
                              vertical: AppSpacing.s4,
                            ),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? cs.primaryContainer
                                  : cs.surfaceContainerLow,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.s12),
                            ),
                            child: InkWell(
                              onTap: () => ref
                                  .read(playbackControllerProvider.notifier)
                                  .jumpTo(index),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.s12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.s12,
                                  vertical: AppSpacing.s8,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 24,
                                      child: isCurrent
                                          ? Icon(Icons.graphic_eq_rounded,
                                              size: 18,
                                              color: cs.onPrimaryContainer)
                                          : Text('${index + 1}',
                                              textAlign: TextAlign.center,
                                              style: tt.bodySmall?.copyWith(
                                                  color: cs.onSurfaceVariant)),
                                    ),
                                    const SizedBox(width: AppSpacing.s12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            song.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: tt.bodyMedium?.copyWith(
                                              color: isCurrent
                                                  ? cs.onPrimaryContainer
                                                  : cs.onSurface,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(
                                              height: AppSpacing.s2),
                                          Text(
                                            song.artist,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: tt.bodySmall?.copyWith(
                                              color: isCurrent
                                                  ? cs.onPrimaryContainer
                                                      .withValues(alpha: 0.7)
                                                  : cs.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: Icon(
                                        Icons.drag_handle_rounded,
                                        size: 20,
                                        color: isCurrent
                                            ? cs.onPrimaryContainer
                                                .withValues(alpha: 0.7)
                                            : cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
