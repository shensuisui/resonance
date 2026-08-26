/// 全屏播放页 —— 封面 + 进度 + 控制

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radius.dart';
import '../providers/providers.dart';

class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final position = ref.watch(positionProvider);
    final duration = ref.watch(durationProvider);
    final playMode = ref.watch(playModeProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('正在播放'),
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: song == null
          ? Center(child: Text('暂无播放', style: tt.bodyLarge))
          : Padding(
              padding: const EdgeInsets.all(AppSpacing.s24),
              child: Column(
                children: [
                  const Spacer(),
                  // 封面
                  _buildCover(song, cs),
                  const SizedBox(height: AppSpacing.s32),
                  // 标题 + 歌手
                  Text(
                    song.title,
                    style: tt.headlineSmall,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Text(
                    song.artist,
                    style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(),
                  // 进度条
                  _buildProgress(position, duration, progress, cs, ref),
                  const SizedBox(height: AppSpacing.s24),
                  // 控制按钮
                  _buildControls(isPlaying, playMode, ref, cs),
                  const SizedBox(height: AppSpacing.s32),
                ],
              ),
            ),
    );
  }

  Widget _buildCover(Song song, ColorScheme cs) {
    final size = 280.0;
    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.s24),
        child: Image.network(
          song.coverUrl!,
          width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultCover(cs, size),
        ),
      );
    }
    return _defaultCover(cs, size);
  }

  Widget _defaultCover(ColorScheme cs, double size) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.s24),
      ),
      child: Icon(Icons.music_note_rounded, size: 80, color: cs.onSurfaceVariant),
    );
  }

  Widget _buildProgress(Duration pos, Duration dur, double progress,
      ColorScheme cs, WidgetRef ref) {
    String _fmt(Duration d) {
      final m = d.inMinutes;
      final s = (d.inSeconds % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Slider(
          value: progress.clamp(0.0, 1.0),
          onChanged: (v) {
            final pos = Duration(milliseconds: (v * dur.inMilliseconds).toInt());
            ref.read(playerProvider).seek(pos);
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(pos), style: TextStyle(color: cs.onSurfaceVariant)),
              Text(_fmt(dur), style: TextStyle(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControls(bool isPlaying, PlayMode playMode,
      WidgetRef ref, ColorScheme cs) {
    final player = ref.read(playerProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // 播放模式
        IconButton(
          icon: Icon(_playModeIcon(playMode)),
          iconSize: 32,
          color: cs.onSurfaceVariant,
          onPressed: () {
            final next = switch (playMode) {
              PlayMode.listLoop => PlayMode.singleLoop,
              PlayMode.singleLoop => PlayMode.shuffle,
              PlayMode.shuffle => PlayMode.sequential,
              PlayMode.sequential => PlayMode.listLoop,
            };
            ref.read(playModeProvider.notifier).setMode(next);
          },
        ),
        // 上一曲
        IconButton(
          icon: const Icon(Icons.skip_previous_rounded),
          iconSize: 48,
          onPressed: () => player.previous(),
        ),
        // 播放/暂停
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: cs.primary,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
            iconSize: 36,
            color: cs.onPrimary,
            onPressed: () {
              if (isPlaying) {
                player.pause();
              } else {
                player.resume();
              }
            },
          ),
        ),
        // 下一曲
        IconButton(
          icon: const Icon(Icons.skip_next_rounded),
          iconSize: 48,
          onPressed: () => player.next(),
        ),
        // 收藏占位
        IconButton(
          icon: const Icon(Icons.favorite_border_rounded),
          iconSize: 32,
          color: cs.onSurfaceVariant,
          onPressed: () {},
        ),
      ],
    );
  }

  IconData _playModeIcon(PlayMode mode) {
    return switch (mode) {
      PlayMode.listLoop => Icons.repeat_rounded,
      PlayMode.singleLoop => Icons.repeat_one_rounded,
      PlayMode.shuffle => Icons.shuffle_rounded,
      PlayMode.sequential => Icons.playlist_play_rounded,
    };
  }
}
