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
      // 导入即存歌曲快照，歌单列表/详情直接展示名字与封面
      songSnapshots: {for (final s in songs) s.globalKey: s},
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
    // 收藏数（「我最喜欢」歌单副标题，动态刷新）
    final favCount = ref.watch(favoriteCountProvider).value ?? 0;

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
            tooltip: '新建歌单',
            onPressed: _createPlaylist,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
              children: [
                // 「我最喜欢」特殊歌单：永远第一个，收藏动态驱动
                // 卡片样式与歌曲卡片（SongTile）一致，高亮用 primaryContainer
                _playlistCard(
                  key: const ValueKey('favorite'),
                  title: '我最喜欢',
                  subtitle: '$favCount 首',
                  icon: Icons.favorite_rounded,
                  highlighted: true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const PlaylistDetailPage(playlistId: 'favorite'),
                      ),
                    );
                  },
                ),
                // 用户歌单列表
                if (_playlists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.s48),
                    child: EmptyState(
                      icon: Icons.queue_music_rounded,
                      message: '还没有歌单',
                      hint: '创建歌单，收藏喜欢的音乐',
                      actionLabel: '新建歌单',
                      actionIcon: Icons.add_rounded,
                      onAction: _createPlaylist,
                    ),
                  )
                else
                  for (final pl in _playlists)
                    _playlistCard(
                      key: ValueKey(pl.id),
                      title: pl.name,
                      subtitle: '${pl.songKeys.length} 首',
                      icon: Icons.queue_music_rounded,
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
                    ),
              ],
            ),
    );
  }

  /// 歌单卡片 —— 与 SongTile 同款容器（surfaceContainerLow + 圆角 + 50 封面位）
  ///
  /// highlighted=true 用于「我最喜欢」，配色对齐 SongTile 的当前播放态。
  Widget _playlistCard({
    Key? key,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    bool highlighted = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final containerColor =
        highlighted ? cs.primaryContainer : cs.surfaceContainerLow;
    final titleColor = highlighted ? cs.onPrimaryContainer : cs.onSurface;
    final subtitleColor =
        highlighted ? cs.onPrimaryContainer : cs.onSurfaceVariant;

    return Container(
      key: key,
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
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: highlighted
                        ? cs.onPrimaryContainer.withValues(alpha: 0.12)
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.s12),
                  ),
                  child: Icon(
                    icon,
                    color: highlighted
                        ? cs.onPrimaryContainer
                        : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(color: subtitleColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
