/// 播放队列页 —— 查看当前队列，点击跳转播放
///
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../providers/providers.dart';
import '../theme/app_spacing.dart';
import '../widgets/empty_state.dart';
import '../widgets/queue_song_row.dart';

class QueuePage extends ConsumerWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(playQueueProvider);
    final current = ref.watch(currentSongProvider);

    return Scaffold(
      appBar: AppBar(title: Text('播放队列 (${queue.length})')),
      body: queue.isEmpty
          ? const EmptyState(
              icon: Icons.queue_music_rounded,
              message: '队列为空',
              hint: '播放歌曲后自动加入队列',
            )
          : ListView.builder(
              // 底部留白：浮层迷你条高约 65，避免末项被永久遮挡
              padding: const EdgeInsets.only(
                  top: AppSpacing.s8, bottom: AppSpacing.s64 + AppSpacing.s8),
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
