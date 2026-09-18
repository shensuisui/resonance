/// 播放队列页 —— 查看当前队列，点击跳转播放
///
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../providers/providers.dart';
import '../theme/app_spacing.dart';
import '../widgets/queue_song_row.dart';

class QueuePage extends ConsumerWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final queue = ref.watch(playQueueProvider);
    final current = ref.watch(currentSongProvider);

    return Scaffold(
      appBar: AppBar(title: Text('播放队列 (${queue.length})')),
      body: queue.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.queue_music_rounded,
                      size: 64, color: cs.onSurfaceVariant),
                  const SizedBox(height: AppSpacing.s16),
                  Text('队列为空', style: tt.titleMedium),
                  const SizedBox(height: AppSpacing.s8),
                  Text('播放歌曲后自动加入队列',
                      style:
                          tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
              itemCount: queue.length,
              itemBuilder: (context, index) {
                final song = queue[index];
                final isCurrent = current != null &&
                    current.sourceId == song.sourceId &&
                    current.id == song.id;
                return _QueueTile(
                  index: index,
                  song: song,
                  isCurrent: isCurrent,
                  onTap: () => ref
                      .read(playbackControllerProvider.notifier)
                      .jumpTo(index),
                );
              },
            ),
    );
  }
}

/// 队列项
class _QueueTile extends StatelessWidget {
  final int index;
  final Song song;
  final bool isCurrent;
  final VoidCallback onTap;

  const _QueueTile({
    required this.index,
    required this.song,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 卡片样式复用 QueueSongRow，与队列 Sheet 保持一致
    return QueueSongRow(
      index: index,
      title: song.title,
      artist: song.artist,
      isCurrent: isCurrent,
      onTap: onTap,
    );
  }
}
