/// 最近播放页 —— 按时间倒序展示最近播放列表

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../providers/providers.dart';
import '../widgets/song_tile.dart';
import '../widgets/empty_state.dart';

class RecentPlaysPage extends ConsumerStatefulWidget {
  const RecentPlaysPage({super.key});

  @override
  ConsumerState<RecentPlaysPage> createState() => _RecentPlaysPageState();
}

class _RecentPlaysPageState extends ConsumerState<RecentPlaysPage> {
  @override
  void initState() {
    super.initState();
    // 加载最近播放列表
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(recentPlaysProvider.notifier).load();
    });
  }

  void _onPlaySong(Song song) async {
    final manager = ref.read(sourceManagerProvider);
    try {
      final url = await manager.getSongUrl(song.sourceId, song.id);
      final player = ref.read(playerProvider);
      await player.play(song.copyWith(playUrl: url));
      ref.read(currentSongProvider.notifier).setSong(song);
      ref.read(isPlayingProvider.notifier).setPlaying(true);
      ref.read(recentPlaysServiceProvider).recordPlay(song);
      ref.read(recentPlaysProvider.notifier).load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final songs = ref.watch(recentPlaysProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('最近播放')),
      body: songs.isEmpty
          ? const EmptyState(
              icon: Icons.history_rounded,
              message: '还没有播放记录',
            )
          : ListView.builder(
              itemCount: songs.length,
              itemBuilder: (context, index) {
                return SongTile(
                  song: songs[index],
                  onTap: () => _onPlaySong(songs[index]),
                );
              },
            ),
    );
  }
}
