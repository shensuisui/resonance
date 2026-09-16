/// 专辑页 —— 按专辑名聚合该专辑的歌曲
///
/// 当前规则源无专辑 ID 规则，采用按专辑名搜索 + 过滤的实现方式。
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../providers/providers.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radius.dart';
import '../widgets/song_tile.dart';
import '../widgets/cover_background.dart';

class AlbumPage extends ConsumerStatefulWidget {
  final String albumName;
  final String? artistName;

  const AlbumPage({super.key, required this.albumName, this.artistName});

  @override
  ConsumerState<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends ConsumerState<AlbumPage> {
  List<Song> _songs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final manager = ref.read(sourceManagerProvider);
      final results = await manager.searchAll(keyword: widget.albumName);
      // 过滤：专辑名匹配（+ 歌手名匹配，可选）
      final albumKeyword = widget.albumName.toLowerCase();
      final songs = results
          .expand((r) => r.songs)
          .where((s) {
            final matchAlbum = s.album?.toLowerCase().contains(albumKeyword) ?? false;
            if (widget.artistName != null && matchAlbum) {
              return s.artist.toLowerCase().contains(widget.artistName!.toLowerCase());
            }
            return matchAlbum;
          })
          .toList();
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.albumName)),
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
            Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
            const SizedBox(height: AppSpacing.s16),
            Text('加载失败', style: tt.titleMedium),
            const SizedBox(height: AppSpacing.s8),
            FilledButton.tonal(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_songs.isEmpty) {
      return Center(
        child: Text('未找到相关歌曲',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // 专辑头部（背景：首曲封面主色渐变）
          SliverToBoxAdapter(
            child: CoverBackground(
              coverUrl: _firstCoverUrl,
              fallback: cs.surface,
              topOpacity: 0.3,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s24),
                child: Row(
                  children: [
                    _cover(cs, 96),
                  const SizedBox(width: AppSpacing.s16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.albumName,
                            style: tt.headlineSmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: AppSpacing.s4),
                        if (widget.artistName != null)
                          Text(widget.artistName!,
                              style: tt.bodyMedium
                                  ?.copyWith(color: cs.onSurfaceVariant)),
                        const SizedBox(height: AppSpacing.s4),
                        Text('${_songs.length} 首',
                            style: tt.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
          const SliverToBoxAdapter(child: Divider(height: 1)),
          // 歌曲列表
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final song = _songs[index];
                return SongTile(song: song);
              },
              childCount: _songs.length,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cover(ColorScheme cs, double size) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.s12),
      ),
      child: Icon(Icons.album_rounded, size: 40, color: cs.onSurfaceVariant),
    );
  }

  /// 列表第一首有封面的歌曲封面 URL（专辑背景取色源）
  String? get _firstCoverUrl {
    for (final s in _songs) {
      if (s.coverUrl != null && s.coverUrl!.isNotEmpty) return s.coverUrl;
    }
    return null;
  }
}