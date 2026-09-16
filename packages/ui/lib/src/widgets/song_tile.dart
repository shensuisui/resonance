/// 歌曲列表项 Widget
///
/// 显示封面、标题、歌手、来源标签，点击播放。
/// 所有颜色用 Theme.colorScheme，间距用 AppSpacing。
///
/// 播放状态：内部 watch 全局播放状态——
/// - 当前正在播放的歌曲：封面盖 0.8 黑色 + 白色跳动均衡器动画
/// - 正在请求播放 URL（loading）：封面盖 0.8 黑色 + 白色圈圈动画
library;

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../providers/providers.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radius.dart';

class SongTile extends ConsumerWidget {
  final Song song;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// 歌手名点击回调（传入歌手名），null 则不可点
  final ValueChanged<String>? onArtistTap;

  const SongTile({
    super.key,
    required this.song,
    this.onTap,
    this.trailing,
    this.onArtistTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // 播放状态：当前歌曲 + 播放中 → 跳动动画；请求播放 URL 中 → loading
    final currentKey = ref.watch(currentSongProvider)?.globalKey;
    final isPlaying = ref.watch(isPlayingProvider);
    final loadingKey = ref.watch(playbackLoadingProvider);
    final isCurrent = currentKey == song.globalKey;
    final showOverlay = isCurrent && (isPlaying || loadingKey == song.globalKey);

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s4,
      ),
      leading: _buildCover(cs, showOverlay, isCurrent && loadingKey == song.globalKey, isCurrent && isPlaying),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge,
      ),
      subtitle: _buildSubtitle(theme.textTheme, cs),
      trailing: trailing,
    );
  }

  /// 副标题：歌手（可点击跳转歌手页）· 来源
  Widget _buildSubtitle(TextTheme theme, ColorScheme cs) {
    final baseStyle = theme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final artistStyle = onArtistTap != null
        ? baseStyle?.copyWith(color: cs.primary)
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
        Text(
          ' · ${song.sourceId}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: baseStyle,
        ),
      ],
    );
  }

  /// 封面：叠加播放状态层
  ///
  /// [showOverlay] 无状态时不叠加；[isLoading] 显示白色圈圈；
  /// [isPlaying] 显示白色跳动均衡器动画。
  Widget _buildCover(ColorScheme cs, bool showOverlay, bool isLoading, bool isPlaying) {
    final base = song.coverUrl != null && song.coverUrl!.isNotEmpty
        ? _networkCover(cs)
        : _defaultCover(cs);

    if (!showOverlay) return base;

    return Stack(
      key: const Key('song_tile_playing_overlay'),
      alignment: Alignment.center,
      children: [
        base,
        // 0.8 黑色遮罩
        Positioned.fill(
          child: Container(
            color: Colors.black.withValues(alpha: 0.8),
            child: null,
          ),
        ),
        // 白色状态动画
        if (isLoading)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          )
        else if (isPlaying)
          const _PlayingBarsIndicator(),
      ],
    );
  }

  Widget _networkCover(ColorScheme cs) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.s8),
      child: Image.network(
        song.coverUrl!,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _defaultCover(cs),
      ),
    );
  }

  Widget _defaultCover(ColorScheme cs) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.s8),
      ),
      child: Icon(Icons.music_note, color: cs.onSurfaceVariant, size: 24),
    );
  }
}

/// 播放中的跳动均衡器动画（白色三条竖条）
///
/// 用 AnimationController 让三条竖条高度正弦摆动，模拟音乐播放跳动。
class _PlayingBarsIndicator extends StatefulWidget {
  const _PlayingBarsIndicator();

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
    )..repeat();
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(2),
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

/// Widget 预览：当前正在播放的歌曲（封面黑罩 + 跳动动画）
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

/// Widget 预览：正在请求播放 URL（封面黑罩 + 白圈）
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