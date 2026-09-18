/// 歌单详情页 —— 曲目列表 + 播放 + 排序 + 删除
///
/// 布局（响应式）：
/// - 手机/竖屏：CustomScrollView + SliverAppBar（可伸缩），
///   顶部为 row[封面, col(名称,描述,操作区)]，下方歌曲列表
/// - 宽屏/横屏：Row 布局，左侧 col(封面,名称,描述)，
///   右侧顶部操作区 + 下方歌曲列表
///
/// 特殊歌单：
/// - playlistId == 'favorite'（「我最喜欢」）：歌曲来自收藏（FavoriteSource），
///   支持播放/取消收藏，不允许重命名/删除/排序。
///
/// 功能：
/// - 点击歌曲播放（setQueue + jumpToIndex）
/// - 播放全部
/// - 长按删除歌曲（收藏歌单为取消收藏）
/// - 拖动排序（用户歌单）
/// - 重命名/删除歌单（用户歌单）

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../theme/app_spacing.dart';
import '../providers/providers.dart';
import '../services/playlist_io.dart';
import '../widgets/song_tile.dart';
import '../widgets/empty_state.dart';
import '../widgets/playlist_header.dart';
import '../widgets/cover_palette.dart';

/// 我最喜欢虚拟歌单 id
const String kFavoritePlaylistId = 'favorite';

class PlaylistDetailPage extends ConsumerStatefulWidget {
  final String playlistId;

  const PlaylistDetailPage({super.key, required this.playlistId});

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  Playlist? _playlist;
  List<Song> _songs = [];
  bool _loading = true;

  /// 封面主题色（手机 SliverAppBar 折叠态背景/前景用）
  Color? _headerColor;

  /// 是否为「我最喜欢」特殊歌单
  bool get _isFavorite => widget.playlistId == kFavoritePlaylistId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final manager = ref.read(sourceManagerProvider);

    if (_isFavorite) {
      // 特殊歌单：从 FavoriteSource 读收藏
      final favSource = manager.getSource('favorite') as FavoriteSource?;
      final songs = favSource == null ? <Song>[] : await favSource.getFavoriteSongs();
      if (mounted) {
        setState(() {
          final now = DateTime.now();
          _playlist = Playlist(
            id: kFavoritePlaylistId,
            name: '我最喜欢',
            songKeys: songs.map((s) => s.globalKey).toList(),
            sourceId: 'favorite',
            createdTime: now,
            modifiedTime: now,
          );
          _songs = songs;
          _loading = false;
        });
      }
      return;
    }

    // 用户歌单：从 DAO 读
    final dao = ref.read(playlistDaoProvider);
    final pl = await dao.getPlaylist(widget.playlistId);
    if (pl == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    // 解析 songKeys 为 Song：
    // 元数据（title/artist/cover）优先用写入时的歌曲快照（规则源
    // getSongDetail 不返回元数据，快照根治歌单歌曲名称空白）；
    // 播放地址用 getSongDetail 补充（有时效，不落库）。
    final resolved = <Song?>[];
    for (final key in pl.songKeys) {
      final parts = key.split(':');
      if (parts.length != 2) {
        resolved.add(null);
        continue;
      }
      final snapshot = pl.songSnapshots[key];
      Song? detail;
      try {
        detail = await manager.getSongDetail(parts[0], parts[1]);
      } catch (_) {
        detail = null;
      }
      if (snapshot == null && detail == null) {
        resolved.add(null);
        continue;
      }
      final snap = snapshot;
      resolved.add(Song(
        id: parts[1],
        sourceId: parts[0],
        title: snap != null && snap.title.isNotEmpty
            ? snap.title
            : (detail?.title ?? ''),
        artist: snap != null && snap.artist.isNotEmpty
            ? snap.artist
            : (detail?.artist ?? ''),
        album: snap?.album ?? detail?.album,
        coverUrl: snap != null && (snap.coverUrl?.isNotEmpty ?? false)
            ? snap.coverUrl
            : detail?.coverUrl,
        duration: snap?.duration ?? detail?.duration,
        playUrl: detail?.playUrl,
        lyricUrl: detail?.lyricUrl,
      ));
    }

    if (mounted) {
      setState(() {
        _playlist = pl;
        _songs = resolved.whereType<Song>().toList();
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
    if (_songs.isEmpty) return;
    final player = ref.read(playerProvider);
    player.setQueue(_songs);
    player.jumpToIndex(0);
  }

  /// 播放指定歌曲
  void _playSong(int index) {
    if (_songs.isEmpty) return;
    final player = ref.read(playerProvider);
    player.setQueue(_songs);
    player.jumpToIndex(index);
  }

  /// 移出歌单（用户歌单）/ 取消收藏（收藏歌单）
  Future<void> _removeSong(int index) async {
    if (_isFavorite) {
      // 取消收藏
      final song = _songs[index];
      await ref.read(favoritesProvider.notifier).toggle(song);
      await _load();
      return;
    }
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
      final removedSong = _songs[index];
      await _save(pl.copyWith(songKeys: newKeys));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已移除「${removedSong.title}」'),
            duration: const Duration(seconds: 2),
            action: SnackBarAction(
              label: '撤销',
              // pl 为移除前的歌单快照，恢复原 songKeys
              onPressed: () => _save(pl.copyWith(songKeys: pl.songKeys)),
            ),
          ),
        );
      }
    }
  }

  /// 重命名歌单（仅用户歌单）
  Future<void> _rename() async {
    if (_isFavorite) return;
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

  /// 删除歌单（仅用户歌单）
  Future<void> _deletePlaylist() async {
    if (_isFavorite) return;
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
      final deleted = pl;
      await ref.read(playlistDaoProvider).deletePlaylist(pl.id);
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text('已删除「${deleted.name}」'),
            duration: const Duration(seconds: 2),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () {
                ref.read(playlistDaoProvider).insertPlaylist(deleted);
              },
            ),
          ),
        );
      }
    }
  }

  /// 导出歌单（仅用户歌单）
  Future<void> _export() async {
    if (_isFavorite) return;
    final pl = _playlist;
    if (pl == null) return;
    if (_songs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('歌单还没有歌曲，无法导出')),
        );
      }
      return;
    }

    // 选择格式
    final cs = Theme.of(context).colorScheme;
    final format = await showModalBottomSheet<PlaylistFormat>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s16),
              child: Text('导出歌单', style: Theme.of(context).textTheme.titleMedium),
            ),
            const Divider(height: 1),
            for (final f in PlaylistFormat.values)
              ListTile(
                leading: Icon(_formatIcon(f), color: cs.onSurfaceVariant),
                title: Text(f.label),
                onTap: () => Navigator.pop(context, f),
              ),
          ],
        ),
      ),
    );
    if (format == null) return;

    final ok = await PlaylistIo.exportPlaylist(pl.name, _songs, format);
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出为 ${format.extension.toUpperCase()} 格式')),
      );
    }
  }

  IconData _formatIcon(PlaylistFormat f) {
    return switch (f) {
      PlaylistFormat.m3u => Icons.format_list_bulleted_rounded,
      PlaylistFormat.pls => Icons.playlist_play_rounded,
      PlaylistFormat.json => Icons.data_object_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final pl = _playlist;
    // 响应式：横屏宽屏用左右分栏，否则竖直列表
    // 窄屏用 SliverAppBar 承担顶部栏（含返回）；宽屏无 SliverAppBar，
    // 需外层 AppBar 提供返回按钮与操作菜单。
    return OrientationBuilder(
      builder: (context, orientation) {
        final isWide = orientation == Orientation.landscape;
        // 宽屏：无全宽 AppBar（左列面板自带返回条）；竖屏由 SliverAppBar 承担
        return Scaffold(
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : pl == null
                  ? const EmptyState(
                      icon: Icons.folder_off_rounded,
                      message: '歌单不存在',
                    )
                  : isWide
                      ? _buildWideLayout(pl)
                      : _buildNarrowLayout(pl),
        );
      },
    );
  }

  List<Widget>? _buildPopupActions() {
    return [
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert_rounded),
        onSelected: (value) {
          switch (value) {
            case 'export':
              _export();
            case 'rename':
              _rename();
            case 'delete':
              _deletePlaylist();
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: 'export',
            child: ListTile(
              leading: Icon(Icons.ios_share_rounded),
              title: Text('导出歌单'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'rename',
            child: ListTile(
              leading: Icon(Icons.drive_file_rename_outline_rounded),
              title: Text('重命名'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete_outline_rounded),
              title: Text('删除歌单'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    ];
  }

  // ==================== 手机/竖屏布局（可伸缩 bar） ====================

  Widget _buildNarrowLayout(Playlist pl) {
    final cs = Theme.of(context).colorScheme;
    // 折叠态背景/前景跟随封面主题色（展开态背景由 flexibleSpace 渐变承担）
    final headerBg = _headerColor ?? cs.surfaceContainerLow;

    return CustomScrollView(
      slivers: [
        // 唯一顶部栏：展开时含封面+名称+操作区；收起后仅标题（+ 操作菜单）
        // 背景为封面主题色渐变，折叠后标题配色同步主题色
        SliverAppBar(
          pinned: true,
          expandedHeight: 320,
          backgroundColor: headerBg,
          foregroundColor: _headerColor == null
              ? null
              : CoverPalette.foreground(_headerColor!),
          title: Text(pl.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: _isFavorite ? null : _buildPopupActions(),
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            background: PlaylistHeaderView(
              mode: PlaylistHeaderMode.flexible,
              name: pl.name,
              coverUrl: pl.coverUrl,
              subtitle: '${_songs.length} 首歌曲',
              isFavorite: _isFavorite,
              onPlayAll: _songs.isEmpty ? null : _playAll,
              onColorExtracted: (color) {
                if (!mounted) return;
                setState(() => _headerColor = color);
              },
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: AppSpacing.s8)),
        // 歌曲列表（支持拖动排序或收藏）
        if (_songs.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.music_off_rounded,
              message: '歌单还没有歌曲',
            ),
          )
        else if (_isFavorite)
          SliverList.builder(
            itemCount: _songs.length,
            itemBuilder: (context, index) =>
                _buildSongRow(index, pl, cs),
          )
        else
          SliverReorderableList(
            itemCount: _songs.length,
            onReorder: (oldIndex, newIndex) {
              final keys = [...pl.songKeys];
              if (newIndex > oldIndex) newIndex--;
              final key = keys.removeAt(oldIndex);
              keys.insert(newIndex, key);
              _save(pl.copyWith(songKeys: keys));
            },
            itemBuilder: (context, index) =>
                _buildSongRow(index, pl, cs),
          ),
      ],
    );
  }

  // ==================== 宽屏/横屏布局（左 col 右列表） ====================

  Widget _buildWideLayout(Playlist pl) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：完整信息面板——返回条（AppBar 只占左列）+ 封面充满 +
        // 名称/描述 + 播放全部，背景为封面主题色渐变
        SizedBox(
          width: 300,
          child: PlaylistHeaderView(
            mode: PlaylistHeaderMode.wide,
            name: pl.name,
            coverUrl: pl.coverUrl,
            subtitle: '${_songs.length} 首歌曲',
            isFavorite: _isFavorite,
            onPlayAll: _songs.isEmpty ? null : _playAll,
            onBack: () => Navigator.pop(context),
          ),
        ),
        const VerticalDivider(width: 1),
        // 右侧：顶部操作区 + 歌曲列表
        Expanded(
          child: Column(
            children: [
              // 操作区：左侧「播放全部」由左面板大按钮承担，这里只放
              // 歌单级操作（导出/重命名/删除）与歌曲数，避免重复按钮
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s16, vertical: AppSpacing.s8),
                child: Row(
                  children: [
                    Text(
                      '${_songs.length} 首歌曲',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                    ),
                    const Spacer(),
                    if (!_isFavorite)
                      IconButton(
                        icon: const Icon(Icons.ios_share_rounded),
                        tooltip: '导出歌单',
                        onPressed: _export,
                      ),
                    if (!_isFavorite)
                      IconButton(
                        icon: const Icon(Icons.drive_file_rename_outline_rounded),
                        tooltip: '重命名',
                        onPressed: _rename,
                      ),
                    if (!_isFavorite)
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        tooltip: '删除歌单',
                        onPressed: _deletePlaylist,
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // 歌曲列表
              Expanded(
                child: _songs.isEmpty
                    ? const EmptyState(
                        icon: Icons.music_off_rounded,
                        message: '歌单还没有歌曲',
                      )
                    : _isFavorite
                        ? ListView.builder(
                            itemCount: _songs.length,
                            itemBuilder: (context, index) =>
                                _buildSongRow(index, pl, cs),
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
                            itemBuilder: (context, index) =>
                                _buildSongRow(index, pl, cs),
                          ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 歌曲行（带唯一 key 供 ReorderableListView）
  Widget _buildSongRow(int index, Playlist pl, ColorScheme cs) {
    final song = _songs[index];
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
        trailing: _isFavorite
            ? Icon(Icons.favorite_rounded, color: cs.primary, size: 20)
            : const Icon(Icons.drag_handle_rounded),
      ),
    );
  }
}