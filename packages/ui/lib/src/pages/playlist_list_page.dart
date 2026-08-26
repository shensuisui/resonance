/// 歌单列表页 —— 歌单 CRUD

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radius.dart';
import '../providers/providers.dart';
import '../services/playlist_io.dart';
import '../widgets/empty_state.dart';
import 'playlist_detail_page.dart';

class PlaylistListPage extends ConsumerStatefulWidget {
  const PlaylistListPage({super.key});

  @override
  ConsumerState<PlaylistListPage> createState() => _PlaylistListPageState();
}

class _PlaylistListPageState extends ConsumerState<PlaylistListPage> {
  List<Playlist> _playlists = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    final dao = ref.read(playlistDaoProvider);
    setState(() => _loading = true);
    _playlists = await dao.getAllPlaylists();
    setState(() => _loading = false);
  }

  Future<void> _createPlaylist() async {
    final name = await _showCreateDialog();
    if (name == null || name.trim().isEmpty) return;

    final dao = ref.read(playlistDaoProvider);
    final now = DateTime.now();
    final playlist = Playlist(
      id: 'pl_${now.millisecondsSinceEpoch}',
      name: name.trim(),
      createdTime: now,
      modifiedTime: now,
    );
    await dao.insertPlaylist(playlist);
    await _loadPlaylists();
  }

  Future<String?> _showCreateDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '歌单名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  /// 导入歌单（M3U/PLS/JSON）
  Future<void> _importPlaylist() async {
    final result = await PlaylistIo.importPlaylist();
    if (result == null || result.entries.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入取消或文件无效')),
        );
      }
      return;
    }

    // 将条目转为 Song 并写入 DB
    final songs = PlaylistIo.entriesToSongs(result.entries);
    if (songs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件中没有可导入的歌曲')),
        );
      }
      return;
    }

    final dao = ref.read(playlistDaoProvider);
    final songDao = ref.read(songDaoProvider);
    final now = DateTime.now();
    final name = result.name?.trim().isNotEmpty == true
        ? result.name!.trim()
        : '导入歌单';

    for (final song in songs) {
      await songDao.insertSong(song);
    }

    final playlist = Playlist(
      id: 'pl_${now.millisecondsSinceEpoch}',
      name: name,
      songKeys: songs.map((s) => s.globalKey).toList(),
      createdTime: now,
      modifiedTime: now,
    );
    await dao.insertPlaylist(playlist);
    await _loadPlaylists();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入歌单「$name」，${songs.length} 首歌曲')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('歌单'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: '导入歌单',
            onPressed: _importPlaylist,
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: _createPlaylist,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _playlists.isEmpty
              ? const EmptyState(
                  icon: Icons.queue_music_rounded,
                  message: '还没有歌单，点击 + 创建',
                )
              : ListView.builder(
                  itemCount: _playlists.length,
                  itemBuilder: (context, index) {
                    final pl = _playlists[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s16,
                        vertical: AppSpacing.s4,
                      ),
                      leading: Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AppRadius.s8),
                        ),
                        child: Icon(Icons.queue_music_rounded,
                            color: cs.onSurfaceVariant),
                      ),
                      title: Text(pl.name, style: tt.bodyLarge),
                      subtitle: Text('${pl.songKeys.length} 首',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          )),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PlaylistDetailPage(playlistId: pl.id),
                          ),
                        );
                      },
                      onLongPress: () => _showDeleteDialog(pl),
                    );
                  },
                ),
    );
  }

  Future<void> _showDeleteDialog(Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除歌单'),
        content: Text('确定删除「${playlist.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(playlistDaoProvider).deletePlaylist(playlist.id);
      await _loadPlaylists();
    }
  }
}
