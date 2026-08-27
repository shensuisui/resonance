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
import '../theme/image_headers.dart';
import '../widgets/song_tile.dart';

class DiscoverPage extends ConsumerWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final state = ref.watch(discoverProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('发现')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(discoverProvider.notifier).load(),
        child: _buildBody(context, state, cs, tt),
      ),
    );
  }

  Widget _buildBody(BuildContext context, DiscoverState state,
      ColorScheme cs, TextTheme tt) {
    if (state.loading && state.playlists.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.playlists.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: constraints.maxHeight,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.explore_rounded,
                        size: 64, color: cs.onSurfaceVariant),
                    const SizedBox(height: AppSpacing.s16),
                    Text('暂无推荐歌单', style: tt.titleMedium),
                    if (state.error != null)
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.s16),
                        child: Text(state.error!,
                            style: tt.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis),
                      ),
                    const SizedBox(height: AppSpacing.s8),
                    Text('下拉刷新', style: tt.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.s16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: AppSpacing.s16,
        crossAxisSpacing: AppSpacing.s16,
        childAspectRatio: 0.72,
      ),
      itemCount: state.playlists.length,
      itemBuilder: (context, index) {
        final playlist = state.playlists[index];
        return _PlaylistCard(
          playlist: playlist,
          onTap: () => _openDetail(context, playlist),
        );
      },
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

    return InkWell(
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
    );
  }

  Widget _buildCover(Playlist playlist, ColorScheme cs) {
    final coverUrl = playlist.coverUrl;
    if (coverUrl != null && coverUrl.isNotEmpty) {
      return Image.network(
        coverUrl,
        fit: BoxFit.cover,
        headers: kImageHeaders,
        loadingBuilder: (context, child, progress) {
          // 加载中显示占位，避免空白
          if (progress == null) return child;
          return _defaultCover(cs);
        },
        errorBuilder: (_, _, _) => _defaultCover(cs),
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
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.playlist.name)),
      body: _buildBody(cs, tt),
    );
  }

  Widget _buildBody(ColorScheme cs, TextTheme tt) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                style: tt.bodyMedium?.copyWith(color: cs.error),
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
      return Center(child: Text('该歌单暂无歌曲', style: tt.bodyMedium));
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
      itemCount: _songs.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: AppSpacing.s64),
      itemBuilder: (context, index) {
        final song = _songs[index];
        return SongTile(
          song: song,
          onTap: () => _play(song),
        );
      },
    );
  }
}