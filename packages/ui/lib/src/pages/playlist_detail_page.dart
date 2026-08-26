/// 歌单详情页 —— 曲目列表 + 播放 + 排序 + 删除
///
/// 功能：
/// - 展示歌单内所有歌曲（songKeys → Song，通过 SourceManager 解析）
/// - 点击歌曲播放（setQueue + jumpToIndex）
/// - 播放全部
/// - 长按删除歌曲
/// - 拖动排序（ReorderableListView）
/// - 重命名歌单
/// - 删除歌单

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radius.dart';
import '../providers/providers.dart';
import '../widgets/song_tile.dart';
import '../widgets/empty_state.dart';

class PlaylistDetailPage extends ConsumerStatefulWidget {
  final String playlistId;

  const PlaylistDetailPage({super.key, required this.playlistId});

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  Playlist? _playlist;
  List<Song?> _songs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dao = ref.read(playlistDaoProvider);
    final manager = ref.read(sourceManagerProvider);
    final pl = await dao.getPlaylist(widget.playlistId);
    if (pl == null) {
      setState(() => _loading = false);
      return;
    }

    // 解析 songKeys 为 Song（缺失的源返回 null 占位）
    final resolved = <Song?>[];
    for (final key in pl.songKeys) {
      final parts = key.split(':');
      if (parts.length != 2) {
        resolved.add(null);
        continue;
      }
      try {
        resolved.add(await manager.getSongDetail(parts[0], parts[1]));
      } catch (_) {
        resolved.add(null);
      }
    }

    if (mounted) {
      setState(() {
        _playlist = pl;
        _songs = resolved;
        _loading = false;
      });
    }
  }

  /// 保存歌单（songKeys 变化时调用）
  Future<void> _save(Playlist updated) async {
    final dao = ref.read(playlistDaoProvider);
    await dao.updatePlaylist(updated);
    await _load();
  }

  /// 播放全部
  void _playAll() {
    final songs = _songs.whereType<Song>().toList();
    if (songs.isEmpty) return;
    final player = ref.read(playerProvider);
    player.setQueue(songs);
    player.jumpToIndex(0);
  }

  /// 播放指定歌曲
  void _playSong(int index) {
    final songs = _songs.whereType<Song>().toList();
    if (songs.isEmpty) return;
    final player = ref.read(playerProvider);
    player.setQueue(songs);
    player.jumpToIndex(index);
  }

  /// 删除歌曲
  Future<void> _removeSong(int index) async {
    final pl = _playlist;
    if (pl == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移出歌单'),
        content: Text('将这首歌移出「${pl.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移出'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final newKeys = [...pl.songKeys]..removeAt(index);
      await _save(pl.copyWith(songKeys: newKeys));
    }
  }

  /// 重命名歌单
  Future<void> _rename() async {
    final pl = _playlist;
    if (pl == null) return;
    final controller = TextEditingController(text: pl.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名歌单'),
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
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (newName != null && newName.trim().isNotEmpty) {
      await _save(pl.copyWith(name: newName.trim()));
    }
  }

  /// 删除歌单
  Future<void> _deletePlaylist() async {
    final pl = _playlist;
    if (pl == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除歌单'),
        content: Text('确定删除「${pl.name}」？此操作不可撤销。'),
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
      await ref.read(playlistDaoProvider).deletePlaylist(pl.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pl = _playlist;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(pl?.name ?? '歌单'),
        actions: [
          IconButton(
            icon: const Icon(Icons.drive_file_rename_outline_rounded),
            tooltip: '重命名',
            onPressed: _rename,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: '删除歌单',
            onPressed: _deletePlaylist,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : pl == null
              ? const EmptyState(
                  icon: Icons.folder_off_rounded,
                  message: '歌单不存在',
                )
              : Column(
                  children: [
                    // 头部信息
                    _buildHeader(pl, cs, tt),
                    const Divider(height: 1),
                    // 歌曲列表（可拖动排序）
                    Expanded(
                      child: _songs.isEmpty
                          ? const EmptyState(
                              icon: Icons.music_off_rounded,
                              message: '歌单还没有歌曲',
                            )
                          : ReorderableListView.builder(
                              itemCount: _songs.length,
                              onReorder: (oldIndex, newIndex) {
                                final keys = [...pl.songKeys];
                                if (newIndex > oldIndex) newIndex--;
                                final key = keys.removeAt(oldIndex);
                                keys.insert(newIndex, key);
                                _save(pl.copyWith(songKeys: keys));
                              },
                              itemBuilder: (context, index) {
                                final song = _songs[index];
                                return _buildSongRow(index, song, pl, cs);
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  /// 头部信息：播放全部 + 歌曲数
  Widget _buildHeader(Playlist pl, ColorScheme cs, TextTheme tt) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Row(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.s12),
            ),
            child: Icon(Icons.queue_music_rounded,
                color: cs.onSurfaceVariant, size: 28),
          ),
          const SizedBox(width: AppSpacing.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pl.name, style: tt.titleMedium),
                const SizedBox(height: AppSpacing.s4),
                Text('${pl.songKeys.length} 首歌曲',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          // 播放全部
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('播放全部'),
            onPressed: _playAll,
          ),
        ],
      ),
    );
  }

  /// 歌曲行（带唯一 key 供 ReorderableListView）
  Widget _buildSongRow(int index, Song? song, Playlist pl, ColorScheme cs) {
    // 无法解析的歌曲显示占位
    if (song == null) {
      return ListTile(
        key: ValueKey('pl_${pl.id}_$index'),
        leading: Container(
          width: 48, height: 48,
          color: cs.surfaceContainerHighest,
        ),
        title: Text('未知歌曲', style: TextStyle(color: cs.onSurfaceVariant)),
        trailing: Icon(Icons.error_outline, color: cs.error),
      );
    }
    return Dismissible(
      key: ValueKey('pl_${pl.id}_$index'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: cs.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.s24),
        child: Icon(Icons.remove_circle_outline_rounded, color: cs.onErrorContainer),
      ),
      onDismissed: (_) => _removeSong(index),
      child: SongTile(
        song: song,
        onTap: () => _playSong(index),
        trailing: const Icon(Icons.drag_handle_rounded),
      ),
    );
  }
}
