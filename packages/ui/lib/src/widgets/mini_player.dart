/// 迷你播放器 —— 底部悬浮条
///
/// 显示当前歌曲、播放/暂停按钮、进度条。
/// 点击展开为全屏播放页（S2 后续实现）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radius.dart';
import '../theme/image_headers.dart';
import '../providers/providers.dart';
import '../pages/player_page.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();

    final isPlaying = ref.watch(isPlayingProvider);
    final position = ref.watch(playbackPositionProvider);
    final duration = ref.watch(playbackDurationProvider);
    final cs = Theme.of(context).colorScheme;

    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Material(
      elevation: 4,
      color: cs.surfaceContainerLow,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PlayerPage()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s8,
          ),
          child: Row(
            children: [
              // 封面
              _buildCover(song, cs),
              const SizedBox(width: AppSpacing.s12),
              // 标题 + 进度
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${song.title} - ${song.artist}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 2,
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              // 播放/暂停
              IconButton(
                icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                onPressed: () {
                  final player = ref.read(playerProvider);
                  if (isPlaying) {
                    player.pause();
                  } else {
                    player.resume();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCover(Song song, ColorScheme cs) {
    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.s8),
        child: Image.network(
          song.coverUrl!,
          width: 40, height: 40, fit: BoxFit.cover,
          headers: kImageHeaders,
          errorBuilder: (_, __, ___) => _defaultCover(cs),
        ),
      );
    }
    return _defaultCover(cs);
  }

  Widget _defaultCover(ColorScheme cs) {
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.s8),
      ),
      child: Icon(Icons.music_note, color: cs.onSurfaceVariant, size: 20),
    );
  }
}
