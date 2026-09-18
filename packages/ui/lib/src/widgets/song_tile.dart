/// 歌曲列表项 Widget —— 卡片式（对齐 PixelPlayer EnhancedSongListItem）
///
/// 视觉：圆角卡片容器（surfaceContainerLow），封面 + 标题/歌手·来源 + 尾部操作。
/// 播放状态：
/// - 当前播放：容器变 primaryContainer、封面变圆形、标题用跑马灯、右侧跳动 EQ
/// - 请求播放 URL（loading）：右侧小圈动画
///
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。
library;

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../providers/providers.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radius.dart';
import 'cover_image.dart';
import 'scrollable_text.dart';
import 'shimmer_box.dart' show kDriverMode;

class SongTile extends ConsumerWidget {
  final Song song;
  final VoidCallback? onTap;

  /// 长按回调（进入多选模式等）
  final VoidCallback? onLongPress;

  final Widget? trailing;

  /// 歌手名点击回调（传入歌手名），null 则不可点
  final ValueChanged<String>? onArtistTap;

  /// 专辑名点击回调（传入专辑名），null 则不显示专辑入口
  final ValueChanged<String>? onAlbumTap;

  const SongTile({
    super.key,
    required this.song,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.onArtistTap,
    this.onAlbumTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // 播放状态：当前歌曲 + 播放中 → EQ；请求播放 URL 中 → loading
    final currentKey = ref.watch(currentSongProvider)?.globalKey;
    final isPlaying = ref.watch(isPlayingProvider);
    final loadingKey = ref.watch(playbackLoadingProvider);
    final isCurrent = currentKey == song.globalKey;
    final isLoading = isCurrent && loadingKey == song.globalKey;
    final showEq = isCurrent && isPlaying;

    // 卡片配色：当前播放用 primaryContainer 高亮（对齐 PixelPlayer）
    final containerColor =
        isCurrent ? cs.primaryContainer : cs.surfaceContainerLow;
    final titleColor = isCurrent ? cs.onPrimaryContainer : cs.onSurface;
    final subtitleColor = (isCurrent ? cs.onPrimaryContainer : cs.onSurface)
        .withValues(alpha: 0.7);

    return Container(
      // 横向 16 与 AppBar 标题缩进对齐；纵向 8 让卡片列表有呼吸感
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(AppRadius.s16),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(AppRadius.s16),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s8,
            ),
            child: Row(
              children: [
                _buildCover(cs, isCurrent),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 当前播放：跑马灯标题；其余：单行省略
                      if (showEq)
                        ScrollableText(
                          text: song.title,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: titleColor,
                          ),
                          fadeColor: containerColor,
                        )
                      else
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: titleColor,
                          ),
                        ),
                      const SizedBox(height: AppSpacing.s4),
                      _buildSubtitle(theme.textTheme, subtitleColor),
                    ],
                  ),
                ),
                // 播放状态指示（EQ / loading）
                if (showEq) ...[
                  const SizedBox(width: AppSpacing.s8),
                  _PlayingBarsIndicator(color: titleColor),
                ] else if (isLoading) ...[
                  const SizedBox(width: AppSpacing.s8),
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: titleColor,
                    ),
                  ),
                ],
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.s4),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 副标题：歌手（可点击跳转歌手页）· 来源
  Widget _buildSubtitle(TextTheme theme, Color subtitleColor) {
    final baseStyle = theme.bodySmall?.copyWith(color: subtitleColor);
    final artistStyle = onArtistTap != null
        ? baseStyle?.copyWith(
            decoration: TextDecoration.underline,
            decorationColor: subtitleColor,
          )
        : baseStyle;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: GestureDetector(
            onTap: onArtistTap != null ? () => onArtistTap!(song.artist) : null,
            child: Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: artistStyle,
            ),
          ),
        ),
        if (onAlbumTap != null &&
            song.album != null &&
            song.album!.isNotEmpty) ...[
          Text(' · ', style: baseStyle),
          Flexible(
            child: GestureDetector(
              onTap: () => onAlbumTap!(song.album!),
              child: Text(
                song.album!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: baseStyle?.copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: subtitleColor,
                ),
              ),
            ),
          ),
        ],
        Text(
          ' · ${song.sourceId}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: baseStyle,
        ),
      ],
    );
  }

  /// 封面：50×50 圆角 10（当前播放变圆形，对齐 PixelPlayer）
  Widget _buildCover(ColorScheme cs, bool isCurrent) {
    final radius = isCurrent ? 25.0 : AppRadius.s12;
    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      return CoverImage(
        url: song.coverUrl,
        width: 50,
        height: 50,
        radius: radius,
      );
    }
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(Icons.music_note_rounded,
          size: 24, color: cs.onSurfaceVariant),
    );
  }
}

/// 播放中的跳动均衡器动画（三条竖条）
class _PlayingBarsIndicator extends StatefulWidget {
  /// 竖条颜色（跟随当前内容色）
  final Color color;

  const _PlayingBarsIndicator({required this.color});

  @override
  State<_PlayingBarsIndicator> createState() => _PlayingBarsIndicatorState();
}

class _PlayingBarsIndicatorState extends State<_PlayingBarsIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    // 驱动模式下静态（避免无限动画阻塞自动化 settle）
    if (!kDriverMode) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        // 三条竖条高度：相位错开 1/3 周期的正弦
        return SizedBox(
          width: 18,
          height: 18,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _bar(_height(t, 0.0)),
              _bar(_height(t, 0.33)),
              _bar(_height(t, 0.67)),
            ],
          ),
        );
      },
    );
  }

  /// 竖条高度：0.3~1.0 之间按相位跳动
  double _height(double t, double phase) {
    final x = (t + phase) % 1.0;
    return 0.3 + 0.7 * (1 - (x * 2 - 1).abs());
  }

  Widget _bar(double heightFactor) {
    return Container(
      width: 3,
      height: 16 * heightFactor,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(AppRadius.s4),
      ),
    );
  }
}

/// Widget 预览：有封面的歌曲项
@Preview(name: 'SongTile 带封面', group: 'SongTile')
Widget songTilePreview() {
  return const ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: SongTile(
          song: Song(
            id: '1', sourceId: 'netease', title: '晴天', artist: '周杰伦',
            coverUrl: 'https://example.com/cover.jpg',
          ),
          trailing: Icon(Icons.more_vert),
        ),
      ),
    ),
  );
}

/// Widget 预览：无封面（默认音符图标）
@Preview(name: 'SongTile 无封面', group: 'SongTile')
Widget songTileNoCoverPreview() {
  return const ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: SongTile(
          song: Song(
            id: '2', sourceId: 'local_scan', title: '稻香', artist: '周杰伦',
          ),
        ),
      ),
    ),
  );
}

/// Widget 预览：当前正在播放的歌曲（容器高亮 + 封面圆形 + 跳动 EQ）
@Preview(name: 'SongTile 播放中', group: 'SongTile')
Widget songTilePlayingPreview() {
  final song = Song(
    id: '3', sourceId: 'netease', title: '晴天', artist: '周杰伦',
  );
  final container = ProviderContainer();
  container.read(currentSongProvider.notifier).setSong(song);
  container.read(isPlayingProvider.notifier).setPlaying(true);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(body: SongTile(song: song)),
    ),
  );
}

/// Widget 预览：正在请求播放 URL（loading 小圈）
@Preview(name: 'SongTile 播放加载中', group: 'SongTile')
Widget songTileLoadingPreview() {
  final song = Song(
    id: '4', sourceId: 'netease', title: '稻香', artist: '周杰伦',
  );
  final container = ProviderContainer();
  container.read(currentSongProvider.notifier).setSong(song);
  container.read(playbackLoadingProvider.notifier).setLoading(song.globalKey);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(body: SongTile(song: song)),
    ),
  );
}
