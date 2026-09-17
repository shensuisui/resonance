/// 全屏播放页 —— 封面/歌词 + 进度 + 控制

import 'dart:math' as math;
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
import '../widgets/scrollable_text.dart';
import '../widgets/queue_sheet.dart';
import '../widgets/cover_image.dart';
import 'artist_page.dart';

class PlayerPage extends ConsumerStatefulWidget {
  /// 嵌入模式（PlayerOverlay 全屏面板）：leading 下拉按钮收起覆盖层
  final bool embedded;

  /// 嵌入模式下的收起回调（null 时下拉按钮无操作）
  final VoidCallback? onCollapse;

  const PlayerPage({super.key, this.embedded = false, this.onCollapse});

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
          onPressed: widget.embedded
              ? (widget.onCollapse ?? () {})
              : () => Navigator.pop(context),
        ),
        // 嵌入全屏面板时隐藏 AppBar 阴影，配合封面渐变背景
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          // 播放队列（底部 Sheet：排序/删除/撤销）
          IconButton(
            icon: const Icon(Icons.queue_music_rounded),
            tooltip: '播放队列',
            onPressed: () => showQueueSheet(context),
          ),
          // 封面/歌词切换
          IconButton(
            icon: Icon(_showLyrics
                ? Icons.album_rounded
                : Icons.lyrics_outlined),
            tooltip: _showLyrics ? '显示封面' : '显示歌词',
            onPressed: () => setState(() => _showLyrics = !_showLyrics),
          ),
          // 睡眠定时器
          PopupMenuButton<String>(
            tooltip: '睡眠定时器',
            onSelected: (value) {
              final notifier = ref.read(sleepTimerProvider.notifier);
              switch (value) {
                case '15':
                  notifier.start(const Duration(minutes: 15));
                case '30':
                  notifier.start(const Duration(minutes: 30));
                case '60':
                  notifier.start(const Duration(minutes: 60));
                case '90':
                  notifier.start(const Duration(minutes: 90));
                case 'cancel':
                  notifier.cancel();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: '15', child: Text('15 分钟')),
              PopupMenuItem(value: '30', child: Text('30 分钟')),
              PopupMenuItem(value: '60', child: Text('60 分钟')),
              PopupMenuItem(value: '90', child: Text('90 分钟')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'cancel', child: Text('关闭')),
            ],
            child: _buildSleepTimerButton(),
          ),
        ],
      ),
      body: song == null
          ? Center(child: Text('暂无播放', style: tt.bodyLarge))
          : SafeArea(
              // 底部安全区：控制区不贴系统手势条
              top: false,
              child: CoverBackground(
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
                    _buildProgress(position, duration, progress, isPlaying, cs, ref),
                    const SizedBox(height: AppSpacing.s16),
                    // 控制按钮
                    _buildControls(isPlaying, playMode, ref, cs,
                        song.globalKey),
                    const SizedBox(height: AppSpacing.s24),
                  ],
                ),
              ),
            ),
              ),
    );
  }

  /// 封面 + 标题/歌手（非歌词模式）
  Widget _buildCoverSection(Song song, ColorScheme cs, TextTheme tt) {
    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 封面自适应：取可用宽/高较小者，上限 480（对齐 PixelPlayer 大封面观感）
          final coverSize = math
              .min(constraints.maxWidth, constraints.maxHeight - 120)
              .clamp(200.0, 480.0);
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: _buildCover(song, cs, coverSize),
              ),
              const SizedBox(height: AppSpacing.s32),
          // 标题：过长时跑马灯滚动（两端渐变遮罩）
          ScrollableText(
            text: song.title,
            style: tt.headlineSmall,
            fadeColor: cs.surface,
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
          );
        },
      ),
    );
  }

  Widget _buildCover(Song song, ColorScheme cs, double size) {
    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      return CoverImage(
        url: song.coverUrl,
        width: size,
        height: size,
        radius: AppRadius.s24,
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
      bool isPlaying, ColorScheme cs, WidgetRef ref) {
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
          iconSize: 36,
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
          iconSize: 56,
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
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: cs.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 40,
              color: cs.onPrimary,
            ),
          ),
        ),
        // 下一曲
        IconButton(
          icon: const Icon(Icons.skip_next_rounded),
          iconSize: 56,
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
          iconSize: 36,
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


  /// 睡眠定时器按钮：关闭时显示图标，倒计时中显示剩余时间
  Widget _buildSleepTimerButton() {
    final cs = Theme.of(context).colorScheme;
    final remaining = ref.watch(sleepTimerProvider);
    if (remaining == null) {
      return const Icon(Icons.bedtime_outlined);
    }
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$minutes:${seconds.toString().padLeft(2, '0')}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.primary),
          ),
          const SizedBox(width: AppSpacing.s4),
          const Icon(Icons.bedtime_rounded),
        ],
      ),
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
