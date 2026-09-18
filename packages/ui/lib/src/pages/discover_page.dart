/// 发现页 —— 聚合各源推荐歌单
///
/// 网格展示歌单封面 + 名称，点击进入歌单详情（从源加载曲目并播放）。
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../providers/providers.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radius.dart';
import '../widgets/song_tile.dart';
import '../widgets/empty_state.dart';
import 'source_management_page.dart';
import '../widgets/playlist_header.dart';
import '../widgets/cover_palette.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/cover_image.dart';
import '../widgets/horizontal_fade.dart';

class DiscoverPage extends ConsumerWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final state = ref.watch(discoverProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('发现')),
      body: _buildBody(
          ref, context, state, cs, tt, ref.watch(recentPlaysProvider)),
    );
  }

  Widget _buildBody(WidgetRef ref, BuildContext context, DiscoverState state,
      ColorScheme cs, TextTheme tt, List<Song> recentSongs) {
    if (state.loading && state.playlists.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(discoverProvider.notifier).load(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // 首页化：最近播放横滑区
          if (recentSongs.isNotEmpty)
            SliverToBoxAdapter(
              child: _buildRecentSection(ref, recentSongs, cs, tt),
            ),
          // 首页化：快捷入口（源管理）
          if (!state.loading)
            SliverToBoxAdapter(
              child: _buildQuickActions(context, cs, tt),
            ),
          // 推荐歌单
          if (state.playlists.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmpty(cs, tt, state.error),
            )
          else ...[
            // 小节标题：与「最近播放」「热门推荐」同一层级样式
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.s16,
                    AppSpacing.s24, AppSpacing.s16, AppSpacing.s8),
                child: Text('推荐歌单',
                    style: tt.titleSmall?.copyWith(color: cs.primary)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s16, 0, AppSpacing.s16, AppSpacing.s16),
              sliver: SliverGrid(
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  mainAxisSpacing: AppSpacing.s16,
                  crossAxisSpacing: AppSpacing.s16,
                  childAspectRatio: 0.72,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final playlist = state.playlists[index];
                    return _PlaylistCard(
                      playlist: playlist,
                      onTap: () => _openDetail(context, playlist),
                    );
                  },
                  childCount: state.playlists.length,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 推荐歌单空态
  Widget _buildEmpty(ColorScheme cs, TextTheme tt, String? error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.explore_rounded, size: 64, color: cs.onSurfaceVariant),
          const SizedBox(height: AppSpacing.s16),
          Text('暂无推荐歌单', style: tt.titleMedium),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s16),
              child: Text(error,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ),
          const SizedBox(height: AppSpacing.s8),
          Text('下拉刷新',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  /// 最近播放横滑区（最多 10 首）
  Widget _buildRecentSection(
      WidgetRef ref, List<Song> songs, ColorScheme cs, TextTheme tt) {
    final items = songs.take(10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16, AppSpacing.s16, AppSpacing.s16, AppSpacing.s8),
          child: Text('最近播放',
              style: tt.titleSmall?.copyWith(color: cs.primary)),
        ),
        SizedBox(
          height: 118,
          child: Stack(
            children: [
              ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
                itemCount: items.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.s12),
                itemBuilder: (context, index) {
                  final song = items[index];
                  return _RecentSongCard(
                    song: song,
                    onTap: () => ref
                        .read(playbackControllerProvider.notifier)
                        .playSong(song),
                  );
                },
              ),
              // 右缘渐隐：提示横向内容可继续滑动
              if (items.length > 3)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: HorizontalFade(color: cs.surface),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 快捷入口：紧凑图标按钮（低视觉权重，不与「最近播放」抢焦点）
  Widget _buildQuickActions(BuildContext context, ColorScheme cs, TextTheme tt) {
    return Padding(
      // 与上方「最近播放」卡片、下方歌单网格均留出呼吸空间
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.s16, AppSpacing.s16, AppSpacing.s16, AppSpacing.s8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _QuickActionCard(
          icon: Icons.cloud_outlined,
          label: '音乐源管理',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const SourceManagementPage(),
            ),
          ),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, Playlist playlist) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiscoverPlaylistPage(playlist: playlist),
      ),
    );
  }
}

/// 歌单卡片
class _PlaylistCard extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;

  const _PlaylistCard({required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return PressableScale(
      // 卡片按压缩放；点击仍由 InkWell 承担（避免双重回调）
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.s12),
                child: _buildCover(playlist, cs),
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            // 名称
            Text(
              playlist.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tt.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.s2),
            // 曲目数
            if (playlist.songKeys.isNotEmpty)
              Text(
                '${playlist.songKeys.length} 首',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(Playlist playlist, ColorScheme cs) {
    final coverUrl = playlist.coverUrl;
    if (coverUrl != null && coverUrl.isNotEmpty) {
      return CoverImage(
        url: coverUrl,
        fit: BoxFit.cover,
        radius: AppRadius.s12,
      );
    }
    return _defaultCover(cs);
  }

  Widget _defaultCover(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Icon(Icons.queue_music_rounded,
          size: 40, color: cs.onSurfaceVariant),
    );
  }
}
/// 最近播放横滑卡片
class _RecentSongCard extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;

  const _RecentSongCard({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SizedBox(
      width: 76,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoverImage(
              url: song.coverUrl,
              width: 76,
              height: 76,
              radius: AppRadius.s12,
            ),
            const SizedBox(height: AppSpacing.s8),
            // 标题与歌手统一两行高度，避免与相邻卡片底部参差
            SizedBox(
              height: 34,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 快捷入口卡片（源管理等）
class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12, vertical: AppSpacing.s8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: AppSpacing.s8),
              Text(label, style: tt.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// 发现页歌单详情 —— 从源加载曲目并展示/播放
class DiscoverPlaylistPage extends ConsumerStatefulWidget {
  final Playlist playlist;

  const DiscoverPlaylistPage({super.key, required this.playlist});

  @override
  ConsumerState<DiscoverPlaylistPage> createState() =>
      _DiscoverPlaylistPageState();
}

class _DiscoverPlaylistPageState extends ConsumerState<DiscoverPlaylistPage> {
  bool _loading = true;
  String? _error;
  List<Song> _songs = const [];

  /// 封面主题色（手机 SliverAppBar 折叠态背景/前景用）
  Color? _headerColor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  MusicSource? get _source => ref
      .read(sourceManagerProvider)
      .getSource(widget.playlist.sourceId ?? '');

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final source = _source;
    if (source == null) {
      setState(() {
        _error = '源 ${widget.playlist.sourceId} 不可用';
        _loading = false;
      });
      return;
    }
    try {
      final songs = await _loadSongs(source, widget.playlist.id);
      if (!mounted) return;
      setState(() {
        _songs = songs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 优先走源的完整歌曲接口（规则源返回含元数据+播放地址的曲目）；
  /// 否则回退为按 songKeys 逐条解析详情。
  Future<List<Song>> _loadSongs(MusicSource source, String id) async {
    final direct = await source.getPlaylistSongs(id);
    if (direct.isNotEmpty) return direct;

    final playlist = await source.getPlaylist(id);
    if (playlist == null || playlist.songKeys.isEmpty) return const [];

    final resolved = await Future.wait(
      playlist.songKeys.map(
        (key) => source
            .getSongDetail(key)
            .then<Song?>((v) => v)
            .catchError((Object _) => null),
      ),
    );
    return resolved.whereType<Song>().toList();
  }

  void _play(Song song) async {
    try {
      await ref.read(playbackControllerProvider.notifier).playSong(song);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('播放失败')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 窄屏用 SliverAppBar 承担顶部栏（含返回）；宽屏无全宽 AppBar，
    // 左列面板自带返回条（AppBar 只占左边）。
    return OrientationBuilder(
      builder: (context, orientation) {
        final isWide = orientation == Orientation.landscape;
        return Scaffold(
          body: isWide ? _buildWideLayout(cs) : _buildNarrowLayout(cs),
        );
      },
    );
  }

  // ==================== 竖屏：可伸缩头部 + 列表 ====================

  Widget _buildNarrowLayout(ColorScheme cs) {
    // 折叠态背景/前景跟随封面主题色
    final headerBg = _headerColor ?? cs.surfaceContainerLow;

    return CustomScrollView(
      slivers: [
        // 唯一顶部栏（复用公共 PlaylistHeaderView），背景为封面主题色渐变
        SliverAppBar(
          pinned: true,
          // 无封面时降低头部高度，避免大面积空白
          expandedHeight:
              (widget.playlist.coverUrl?.isNotEmpty ?? false) ? 320 : 264,
          backgroundColor: headerBg,
          foregroundColor: _headerColor == null
              ? null
              : CoverPalette.foreground(_headerColor!),
          title: Text(widget.playlist.name,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            background: PlaylistHeaderView(
              mode: PlaylistHeaderMode.flexible,
              name: widget.playlist.name,
              coverUrl: widget.playlist.coverUrl,
              subtitle: _subtitleText(),
              onPlayAll: _songs.isEmpty ? null : _playAll,
              onColorExtracted: (color) {
                if (!mounted) return;
                setState(() => _headerColor = color);
              },
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: AppSpacing.s8)),
        if (_loading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: cs.error),
                      textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.s8),
                  TextButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('重新加载'),
                  ),
                ],
              ),
            ),
          )
        else if (_songs.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.music_off_rounded,
              message: '该歌单暂无歌曲',
            ),
          )
        else
          SliverList.builder(
            itemCount: _songs.length,
            itemBuilder: (context, index) => _buildSongRow(index),
          ),
      ],
    );
  }

  // ==================== 横屏：左侧信息 + 右下列表 ====================

  Widget _buildWideLayout(ColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：完整信息面板——返回条（AppBar 只占左列）+ 封面充满 +
        // 名称/描述 + 播放全部，背景为封面主题色渐变
        SizedBox(
          width: 300,
          child: PlaylistHeaderView(
            mode: PlaylistHeaderMode.wide,
            name: widget.playlist.name,
            coverUrl: widget.playlist.coverUrl,
            subtitle: _subtitleText(),
            onPlayAll: _songs.isEmpty ? null : _playAll,
            onBack: () => Navigator.pop(context),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.s16),
                child: Row(
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('播放全部'),
                      onPressed: _songs.isEmpty ? null : _playAll,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _buildSongList(cs)),
            ],
          ),
        ),
      ],
    );
  }

  /// 头部描述文案：有曲目数用曲目数；否则错误信息 / 加载中
  String _subtitleText() {
    if (widget.playlist.songKeys.isNotEmpty) {
      return '${_songs.length} 首歌曲';
    }
    if (_error != null) return _error!;
    return '正在加载...';
  }

  /// 播放全部（远程源：逐首请求播放 URL，会触发列表 loading 状态）
  void _playAll() {
    if (_songs.isEmpty) return;
    final player = ref.read(playerProvider);
    player.setQueue(_songs);
    player.jumpToIndex(0);
  }

  Widget _buildSongList(ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: cs.error),
                textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.s8),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新加载'),
            ),
          ],
        ),
      );
    }
    if (_songs.isEmpty) {
      return const EmptyState(
        icon: Icons.music_off_rounded,
        message: '该歌单暂无歌曲',
      );
    }
    return ListView.builder(
      itemCount: _songs.length,
      itemBuilder: (context, index) => _buildSongRow(index),
    );
  }

  Widget _buildSongRow(int index) {
    final song = _songs[index];
    return SongTile(
      song: song,
      onTap: () => _play(song),
    );
  }
}