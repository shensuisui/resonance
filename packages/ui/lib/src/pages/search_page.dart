/// 搜索页 —— 跨源聚合搜索

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../theme/app_spacing.dart';
import '../providers/providers.dart';
import '../widgets/song_tile.dart';
import '../widgets/empty_state.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSearch() {
    final keyword = _controller.text.trim();
    if (keyword.isNotEmpty) {
      ref.read(searchNotifierProvider.notifier).search(keyword);
    }
  }

  void _onPlaySong(Song song) async {
    // 获取播放 URL
    final manager = ref.read(sourceManagerProvider);
    try {
      final url = await manager.getSongUrl(song.sourceId, song.id);
      final player = ref.read(playerProvider);
      await player.play(song.copyWith(playUrl: url));

      // 更新播放状态
      ref.read(currentSongProvider.notifier).state = song;
      ref.read(isPlayingProvider.notifier).state = true;

      // 记录最近播放
      ref.read(recentPlaysServiceProvider).recordPlay(song);
      ref.read(recentPlaysNotifierProvider.notifier).load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败: $e')),
        );
      }
    }
  }

  /// 将歌曲加入歌单
  Future<void> _addToPlaylist(Song song) async {
    final dao = ref.read(playlistDaoProvider);
    final playlists = await dao.getAllPlaylists();

    if (playlists.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('还没有歌单，请先在歌单页创建')),
        );
      }
      return;
    }

    // 弹出歌单选择器
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.s16),
                child: Text('加入歌单', style: Theme.of(context).textTheme.titleMedium),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final pl = playlists[index];
                    final alreadyHas = pl.songKeys.contains(song.globalKey);
                    return ListTile(
                      leading: Icon(Icons.queue_music_rounded,
                          color: cs.onSurfaceVariant),
                      title: Text(pl.name),
                      subtitle: Text('${pl.songKeys.length} 首'),
                      trailing: alreadyHas
                          ? Icon(Icons.check_rounded, color: cs.primary)
                          : null,
                      onTap: () => Navigator.pop(context, pl.id),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected == null) return;
    final pl = playlists.firstWhere((p) => p.id == selected);
    final alreadyHas = pl.songKeys.contains(song.globalKey);

    if (!alreadyHas) {
      await dao.updatePlaylist(
        pl.copyWith(songKeys: [...pl.songKeys, song.globalKey]),
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(alreadyHas
              ? '已在该歌单中'
              : '已加入「${pl.name}」'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          decoration: const InputDecoration(
            hintText: '搜索歌曲、歌手',
            border: InputBorder.none,
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _onSearch(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: _onSearch,
          ),
        ],
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : state.results.isEmpty
              ? EmptyState(
                  message: state.keyword.isEmpty
                      ? '搜索你喜欢的音乐'
                      : '没有找到 "${state.keyword}" 的结果',
                )
              : ListView.builder(
                  itemCount: state.results.length,
                  itemBuilder: (context, index) {
                    final song = state.results[index];
                    return SongTile(
                      song: song,
                      onTap: () => _onPlaySong(song),
                      trailing: IconButton(
                        icon: const Icon(Icons.playlist_add_rounded),
                        tooltip: '加入歌单',
                        onPressed: () => _addToPlaylist(song),
                      ),
                    );
                  },
                ),
    );
  }
}
