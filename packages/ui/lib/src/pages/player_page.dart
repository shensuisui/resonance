/// 全屏播放页 —— 对齐 PixelPlayer 播放器布局
///
/// 视觉结构（参考 PixelPlayer FullPlayerContent 竖屏）：
/// - 大封面（自适应，暂停时轻微缩小）
/// - 元信息区（左对齐：标题 / 歌手 + 右侧歌词切换按钮）
/// - 进度区（Slider + 下方左时长/右总长）
/// - 控制区两行：transport（等宽三按钮：上一首/播放/下一首）+ 开关行
///   （胶囊容器内三个等宽 segment：随机/循环/收藏）
///
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。
library;

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

    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          tooltip: '收起',
          onPressed: widget.embedded
              ? (widget.onCollapse ?? () {})
              : () => Navigator.pop(context),
        ),
        // 顶部仅承载队列与定时器等次要操作，歌曲信息在内容区左对齐展示
        title: const SizedBox.shrink(),
        actions: [
          IconButton(
            icon: const Icon(Icons.queue_music_rounded),
            tooltip: '播放队列',
            onPressed: () => showQueueSheet(context),
          ),
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: song == null
          ? const Center(child: Text('暂无播放'))
          : SafeArea(
              top: false,
              child: CoverBackground(
                coverUrl: song.coverUrl,
                fallback: cs.surface,
                topOpacity: 0.35,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s24),
                  child: Column(
                    children: [
                      // 1. 大封面（或歌词）
                      Expanded(
                        child: _showLyrics
                            ? const LyricsView()
                            : _buildCoverArea(song, cs, isPlaying),
                      ),
                      const SizedBox(height: AppSpacing.s16),
                      // 2. 元信息（左对齐）+ 歌词切换
                      _buildMetadataRow(song, cs),
                      const SizedBox(height: AppSpacing.s4),
                      // 3. 进度 + 时间
                      _buildProgress(position, duration, progress, cs),
                      const SizedBox(height: AppSpacing.s12),
                      // 4. 控制区：transport + 开关行
                      _buildTransportRow(isPlaying, cs),
                      const SizedBox(height: AppSpacing.s12),
                      _buildToggleRow(playMode, cs, song.globalKey),
                      // 底部留白：避免开关行贴住系统手势条
                      const SizedBox(height: AppSpacing.s24),
                    ],
                  ),
                ),
              ),
            ),
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

  // ==================== 封面区 ====================

  /// 大封面（自适应尺寸，暂停时轻微缩小）
  Widget _buildCoverArea(Song song, ColorScheme cs, bool isPlaying) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math
            .min(constraints.maxWidth, constraints.maxHeight - 24)
            .clamp(200.0, 480.0);
        return AnimatedScale(
          // 暂停时 0.95 缩小（对齐 PixelPlayer 封面“停顿挤压”反馈）
          scale: isPlaying ? 1.0 : 0.95,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: _buildCover(song, cs, size),
        );
      },
    );
  }

  Widget _buildCover(Song song, ColorScheme cs, double size) {
    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      return CoverImage(
        url: song.coverUrl,
        width: size,
        height: size,
        radius: AppRadius.s16,
      );
    }
    return _defaultCover(cs, size);
  }

  Widget _defaultCover(ColorScheme cs, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.s16),
      ),
      child: Icon(Icons.music_note_rounded,
          size: size * 0.28, color: cs.onSurfaceVariant),
    );
  }

  // ==================== 元信息区（左对齐） ====================

  Widget _buildMetadataRow(Song song, ColorScheme cs) {
    final tt = Theme.of(context).textTheme;
    return SizedBox(
      // 与 PixelPlayer 一致：元信息行最小高度 70，保证标题/歌手有稳定节奏
      width: double.infinity,
      child: Row(
        children: [
          // 标题 + 歌手（左对齐，对齐 PixelPlayer）
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ScrollableText(
                  text: song.title,
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                  fadeColor: cs.surface,
                ),
                const SizedBox(height: AppSpacing.s4),
                GestureDetector(
                  onTap: song.artist.isEmpty
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ArtistPage(artistName: song.artist),
                            ),
                          ),
                  child: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          // 歌词切换（圆角 chip，对齐 PixelPlayer 元信息行右侧按钮）
          _buildLyricsButton(cs),
        ],
      ),
    );
  }

  Widget _buildLyricsButton(ColorScheme cs) {
    return PressableScale(
      onTap: () => setState(() => _showLyrics = !_showLyrics),
      pressedScale: 0.94,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: _showLyrics
              ? cs.primary
              : cs.primaryContainer.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(AppRadius.s16),
        ),
        child: Icon(
          _showLyrics ? Icons.album_rounded : Icons.lyrics_outlined,
          size: 24,
          color: _showLyrics ? cs.onPrimary : cs.onPrimaryContainer,
        ),
      ),
    );
  }

  // ==================== 进度区 ====================

  Widget _buildProgress(Duration pos, Duration dur, double progress,
      ColorScheme cs) {
    String fmt(Duration d) {
      final m = d.inMinutes;
      final s = (d.inSeconds % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }

    final tt = Theme.of(context).textTheme;
    final labelStyle =
        tt.bodySmall?.copyWith(fontSize: 12, fontWeight: FontWeight.w600);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: cs.primary,
            inactiveTrackColor: cs.onSurface.withValues(alpha: 0.2),
            thumbColor: cs.primary,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(
            value: progress.clamp(0.0, 1.0),
            onChanged: (v) {
              final p =
                  Duration(milliseconds: (v * dur.inMilliseconds).toInt());
              ref.read(playerProvider).seek(p);
            },
            onChangeEnd: (_) => HapticFeedback.selectionClick(),
          ),
        ),
        // 时间标签：左当前 / 右总长（对齐 PixelPlayer EfficientTimeLabels）
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(fmt(pos), style: labelStyle),
            Text(fmt(dur), style: labelStyle),
          ],
        ),
      ],
    );
  }

  // ==================== 控制区两行 ====================

  /// transport：上一首 / 播放-暂停 / 下一首（等宽，圆形容器）
  Widget _buildTransportRow(bool isPlaying, ColorScheme cs) {
    return SizedBox(
      height: 80,
      child: Row(
        children: [
          Expanded(child: _transportButton(
            icon: Icons.skip_previous_rounded,
            background: cs.secondaryContainer,
            foreground: cs.onSecondaryContainer,
            onTap: () {
              HapticFeedback.selectionClick();
              ref.read(playerProvider).previous();
            },
          )),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            flex: 2,
            child: _transportButton(
              icon: isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              background: cs.primary,
              foreground: cs.onPrimary,
              iconSize: 40,
              onTap: () {
                HapticFeedback.selectionClick();
                final player = ref.read(playerProvider);
                if (isPlaying) {
                  player.pause();
                } else {
                  player.resume();
                }
              },
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(child: _transportButton(
            icon: Icons.skip_next_rounded,
            background: cs.secondaryContainer,
            foreground: cs.onSecondaryContainer,
            onTap: () {
              HapticFeedback.selectionClick();
              ref.read(playerProvider).next();
            },
          )),
        ],
      ),
    );
  }

  Widget _transportButton({
    required IconData icon,
    required Color background,
    required Color foreground,
    required VoidCallback onTap,
    double iconSize = 32,
  }) {
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.94,
      child: Container(
        height: double.infinity,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Icon(icon, size: iconSize, color: foreground),
      ),
    );
  }

  /// 开关行：胶囊容器内三个等宽 segment（随机 / 循环 / 收藏）
  Widget _buildToggleRow(
      PlayMode playMode, ColorScheme cs, String? songKey) {
    final isShuffle = playMode == PlayMode.shuffle;
    final isFavorite =
        songKey != null && ref.watch(isFavoriteProvider(songKey)).value == true;
    final isSequential = playMode == PlayMode.sequential;
    final repeatIcon = playMode == PlayMode.singleLoop
        ? Icons.repeat_one_rounded
        : Icons.repeat_rounded;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Expanded(
            child: _toggleSegment(
              icon: Icons.shuffle_rounded,
              active: isShuffle,
              activeBackground: cs.primaryContainer,
              activeForeground: cs.onPrimaryContainer,
              inactiveForeground: cs.onSurface,
              tooltip: '随机播放',
              onTap: () => ref
                  .read(playModeProvider.notifier)
                  .setMode(isShuffle ? PlayMode.listLoop : PlayMode.shuffle),
            ),
          ),
          const SizedBox(width: AppSpacing.s4),
          Expanded(
            child: _toggleSegment(
              icon: repeatIcon,
              active: !isShuffle && !isSequential,
              activeBackground: cs.secondaryContainer,
              activeForeground: cs.onSecondaryContainer,
              inactiveForeground: cs.onSurface,
              tooltip: '循环模式',
              onTap: () {
                // 循环：列表循环 → 单曲循环 → 顺序播放 → 列表循环
                final next = switch (playMode) {
                  PlayMode.listLoop => PlayMode.singleLoop,
                  PlayMode.singleLoop => PlayMode.sequential,
                  PlayMode.sequential => PlayMode.listLoop,
                  PlayMode.shuffle => PlayMode.listLoop,
                };
                ref.read(playModeProvider.notifier).setMode(next);
              },
            ),
          ),
          const SizedBox(width: AppSpacing.s4),
          Expanded(
            child: _toggleSegment(
              icon: isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              active: isFavorite,
              activeBackground: cs.tertiaryContainer,
              activeForeground: cs.onTertiaryContainer,
              inactiveForeground: cs.onSurface,
              tooltip: isFavorite ? '取消收藏' : '收藏',
              onTap: () async {
                final key = songKey;
                final current = ref.read(currentSongProvider);
                if (key == null || current == null) return;
                HapticFeedback.selectionClick();
                await ref.read(favoritesProvider.notifier).toggle(current);
                ref.invalidate(isFavoriteProvider(key));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleSegment({
    required IconData icon,
    required bool active,
    required Color activeBackground,
    required Color activeForeground,
    required Color inactiveForeground,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: PressableScale(
        onTap: onTap,
        pressedScale: 0.96,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 48,
          decoration: BoxDecoration(
            color: active
                ? activeBackground
                : cs.onSurface.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(
            icon,
            size: 22,
            color: active ? activeForeground : inactiveForeground,
          ),
        ),
      ),
    );
  }
}
