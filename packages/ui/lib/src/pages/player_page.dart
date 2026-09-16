/// 全屏播放页 —— 封面/歌词 + 进度 + 控制

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radius.dart';
import '../providers/providers.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/cover_background.dart';
import '../widgets/pressable_scale.dart';
import 'artist_page.dart';
import 'queue_page.dart';

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  /// 是否显示歌词（false 显示封面）
  bool _showLyrics = false;

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(currentSongProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final position = ref.watch(playbackPositionProvider);
    final duration = ref.watch(playbackDurationProvider);
    final playMode = ref.watch(playModeProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(_showLyrics ? '歌词' : song?.title ?? '正在播放'),
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // 播放队列
          IconButton(
            icon: const Icon(Icons.queue_music_rounded),
            tooltip: '播放队列',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const QueuePage()),
            ),
          ),
          // 封面/歌词切换
          IconButton(
            icon: Icon(_showLyrics
                ? Icons.album_rounded
                : Icons.lyrics_outlined),
            tooltip: _showLyrics ? '显示封面' : '显示歌词',
            onPressed: () => setState(() => _showLyrics = !_showLyrics),
          ),
        ],
      ),
      body: song == null
          ? Center(child: Text('暂无播放', style: tt.bodyLarge))
          : CoverBackground(
              // 播放页沉浸背景：封面主色(顶部淡色) → 表面色(底部)
              coverUrl: song.coverUrl,
              fallback: cs.surface,
              topOpacity: 0.35,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s24),
                child: Column(
                  children: [
                    // 上部：封面或歌词
                    _showLyrics
                        ? const Expanded(child: LyricsView())
                        : _buildCoverSection(song, cs, tt),
                    const SizedBox(height: AppSpacing.s16),
                    // 进度条
                    _buildProgress(position, duration, progress, cs, ref),
                    const SizedBox(height: AppSpacing.s16),
                    // 控制按钮
                    _buildControls(isPlaying, playMode, ref, cs,
                        song.globalKey),
                    const SizedBox(height: AppSpacing.s24),
                  ],
                ),
              ),
            ),
    );
  }

  /// 封面 + 标题/歌手（非歌词模式）
  Widget _buildCoverSection(Song song, ColorScheme cs, TextTheme tt) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 封面等比缩放：剩余高度不足时（矮窗口/小屏）自动缩小，
          // 避免固定 280px 封面 + 文本超出可用空间溢出
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _buildCover(song, cs),
            ),
          ),
          const SizedBox(height: AppSpacing.s32),
          Text(
            song.title,
            style: tt.headlineSmall,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s8),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ArtistPage(artistName: song.artist),
              ),
            ),
            child: Text(
              song.artist,
              style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
        ],
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
          // 拖动结束轻触觉反馈
          onChangeEnd: (_) => HapticFeedback.selectionClick(),
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
      WidgetRef ref, ColorScheme cs, String? songKey) {
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
        // 播放/暂停（按压缩放 + 触觉反馈）
        PressableScale(
          pressedScale: 0.92,
          onTap: () {
            HapticFeedback.selectionClick();
            if (isPlaying) {
              player.pause();
            } else {
              player.resume();
            }
          },
          child: Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: cs.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 36,
              color: cs.onPrimary,
            ),
          ),
        ),
        // 下一曲
        IconButton(
          icon: const Icon(Icons.skip_next_rounded),
          iconSize: 48,
          onPressed: () => player.next(),
        ),
        // 收藏
        IconButton(
          icon: Icon(
            (songKey != null &&
                    ref.watch(isFavoriteProvider(songKey)).value == true)
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
          ),
          iconSize: 32,
          color: cs.onSurfaceVariant,
          onPressed: () async {
            final key = songKey;
            final current = ref.read(currentSongProvider);
            if (key == null || current == null) return;
            await ref.read(favoritesProvider.notifier).toggle(current);
            ref.invalidate(isFavoriteProvider(key));
          },
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
