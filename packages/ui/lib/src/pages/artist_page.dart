/// 歌手页 —— 按歌手名聚合该歌手的歌曲
///
/// 当前规则源无歌手 ID 规则，采用按名字搜索的实现方式。
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../providers/providers.dart';
import '../theme/app_spacing.dart';
import '../widgets/song_tile.dart';

class ArtistPage extends ConsumerStatefulWidget {
  final String artistName;

  const ArtistPage({super.key, required this.artistName});

  @override
  ConsumerState<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends ConsumerState<ArtistPage> {
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
      final results = await manager.searchAll(keyword: widget.artistName);
      // 过滤：歌手字段匹配关键词（避免同名无关歌曲混入）
      final keyword = widget.artistName.toLowerCase();
      final songs = results
          .expand((r) => r.songs)
          .where((s) => s.artist.toLowerCase().contains(keyword))
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
      appBar: AppBar(title: Text(widget.artistName)),
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
          // 歌手头部
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s24),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: cs.surfaceContainerHighest,
                    child: Icon(Icons.person_rounded,
                        size: 40, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: AppSpacing.s16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.artistName,
                            style: tt.headlineSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
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
}
