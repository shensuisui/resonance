/// 发现页 —— 聚合各源推荐歌单
///
/// 网格展示歌单封面 + 名称，点击进入歌单详情。
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../providers/providers.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radius.dart';

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
        child: _buildBody(context, ref, state, cs, tt),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, DiscoverState state,
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
                            textAlign: TextAlign.center),
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
          onTap: () => _openDetail(context, ref, playlist),
        );
      },
    );
  }

  void _openDetail(BuildContext context, WidgetRef ref, Playlist playlist) {
    // 歌单详情页期望接收完整的歌单歌曲列表，
    // 这里尝试从源获取歌单详情后跳转
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
        errorBuilder: (_, __, ___) => _defaultCover(cs),
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

/// 发现页歌单详情（展示歌单歌曲列表）
class DiscoverPlaylistPage extends ConsumerWidget {
  final Playlist playlist;

  const DiscoverPlaylistPage({super.key, required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(playlist.name)),
      body: playlist.songKeys.isEmpty
          ? Center(
              child: Text('该歌单暂无歌曲', style: tt.bodyMedium),
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.s16),
              children: [
                // 封面 + 信息头部
                Row(
                  children: [
                    _cover(cs, 96),
                    const SizedBox(width: AppSpacing.s16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(playlist.name,
                              style: tt.titleLarge, maxLines: 2),
                          const SizedBox(height: AppSpacing.s8),
                          Text(
                            '${playlist.songKeys.length} 首 · 来自 ${playlist.sourceId}',
                            style: tt.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(),
                // 提示：歌曲需点击源歌单打开（songKeys 为源内 id）
                Text(
                  '该歌单来自 ${playlist.sourceId} 源，歌曲数据需从源加载',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
    );
  }

  Widget _cover(ColorScheme cs, double size) {
    final url = playlist.coverUrl;
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.s12),
        child: Image.network(url,
            width: size, height: size, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _defaultCover(cs, size)),
      );
    }
    return _defaultCover(cs, size);
  }

  Widget _defaultCover(ColorScheme cs, double size) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.s12),
      ),
      child: Icon(Icons.queue_music_rounded, color: cs.onSurfaceVariant),
    );
  }
}
