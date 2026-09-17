/// 搜索页 —— 跨源聚合搜索

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radius.dart';
import '../providers/providers.dart';
import '../widgets/song_tile.dart';
import '../widgets/empty_state.dart';
import '../widgets/download_button.dart';
import 'artist_page.dart';
import 'discover_page.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();

  /// 多选模式：已选歌曲全局键
  final Set<String> _selected = {};

  /// 是否处于多选模式
  bool get _selectionMode => _selected.isNotEmpty;

  /// 多选模式下切换勾选；非多选时按语义走 onTap 外层逻辑
  void _toggleSelect(Song song) {
    setState(() {
      if (!_selected.add(song.globalKey)) {
        _selected.remove(song.globalKey);
      }
    });
  }

  /// 长按进入多选
  void _onLongPress(Song song) {
    setState(() => _selected.add(song.globalKey));
  }

  /// 清空多选
  void _clearSelection() => setState(_selected.clear);

  /// 已选歌曲集合（按当前全部结果顺序）
  List<Song> _selectedSongs(List<Song> all) =>
      all.where((s) => _selected.contains(s.globalKey)).toList();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSearch() {
    final keyword = _controller.text.trim();
    if (keyword.isNotEmpty) {
      ref.read(searchProvider.notifier).search(keyword);
    }
  }

  void _onPlaySong(Song song) async {
    try {
      await ref.read(playbackControllerProvider.notifier).playSong(song);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败: $e')),
        );
      }
    }
  }

  /// 弹出歌单选择器，返回选中的歌单（无歌单/取消返回 null）
  Future<Playlist?> _pickPlaylist() async {
    final dao = ref.read(playlistDaoProvider);
    final playlists = await dao.getAllPlaylists();

    if (playlists.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('还没有歌单，请先在歌单页创建')),
        );
      }
      return null;
    }

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
                child: Text('加入歌单',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final pl = playlists[index];
                    return ListTile(
                      leading: Icon(Icons.queue_music_rounded,
                          color: cs.onSurfaceVariant),
                      title: Text(pl.name),
                      subtitle: Text('${pl.songKeys.length} 首'),
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

    if (selected == null) return null;
    return playlists.firstWhere((p) => p.id == selected);
  }

  /// 将歌曲写入歌单（去重），返回是否已在歌单中
  Future<bool> _addSongToPlaylist(Song song, Playlist pl) async {
    final dao = ref.read(playlistDaoProvider);
    final alreadyHas = pl.songKeys.contains(song.globalKey);
    if (!alreadyHas) {
      // 写入歌曲快照：规则源详情不返回元数据，快照保证歌单列表/详情有名字
      final newSnapshots = Map<String, Song>.from(pl.songSnapshots)
        ..[song.globalKey] = song;
      await dao.updatePlaylist(
        pl.copyWith(
          songKeys: [...pl.songKeys, song.globalKey],
          songSnapshots: newSnapshots,
        ),
      );
    }
    return alreadyHas;
  }

  /// 将歌曲加入歌单
  Future<void> _addToPlaylist(Song song) async {
    final pl = await _pickPlaylist();
    if (pl == null) return;
    final alreadyHas = await _addSongToPlaylist(song, pl);
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

  /// 批量：已选歌曲加入歌单
  Future<void> _addSelectedToPlaylist(List<Song> all) async {
    final songs = _selectedSongs(all);
    if (songs.isEmpty) return;
    final pl = await _pickPlaylist();
    if (pl == null) return;
    var added = 0;
    for (final s in songs) {
      if (!await _addSongToPlaylist(s, pl)) added++;
    }
    _clearSelection();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已加入 $added 首到「${pl.name}」')),
      );
    }
  }

  /// 批量：已选歌曲下载
  Future<void> _downloadSelected(List<Song> all) async {
    final songs = _selectedSongs(all);
    if (songs.isEmpty) return;
    final manager = ref.read(downloadManagerProvider);
    var ok = 0;
    for (final s in songs) {
      try {
        await manager.download(s);
        ok++;
      } catch (_) {
        // 单曲失败不影响批量继续
      }
    }
    _clearSelection();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已下载 $ok/${songs.length} 首')),
      );
    }
  }

  /// 空闲态：搜索历史 + 热门推荐
  Widget _buildIdle(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final history = ref.watch(searchHistoryProvider);
    final discover = ref.watch(discoverProvider);
    final sections = <Widget>[];

    // 搜索历史
    if (history.isNotEmpty) {
      sections.add(Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.s16, AppSpacing.s16, AppSpacing.s8, AppSpacing.s4),
        child: Row(
          children: [
            Expanded(
              child: Text('搜索历史',
                  style: tt.titleSmall?.copyWith(color: cs.primary)),
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, size: 20),
              tooltip: '清空历史',
              onPressed: () => ref.read(searchHistoryProvider.notifier).clear(),
            ),
          ],
        ),
      ));
      sections.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
        child: Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: history
              .map((keyword) => InputChip(
                    label: Text(keyword),
                    onPressed: () {
                      _controller.text = keyword;
                      ref.read(searchProvider.notifier).search(keyword);
                    },
                    onDeleted: () => ref
                        .read(searchHistoryProvider.notifier)
                        .remove(keyword),
                  ))
              .toList(),
        ),
      ));
    }

    // 热门推荐（复用发现页数据源：各源 getPlaylistList）
    if (discover.playlists.isNotEmpty) {
      sections.add(Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.s16, AppSpacing.s24, AppSpacing.s16, AppSpacing.s8),
        child: Text('热门推荐',
            style: tt.titleSmall?.copyWith(color: cs.primary)),
      ));
      sections.add(SizedBox(
        height: 180,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
          scrollDirection: Axis.horizontal,
          itemCount: discover.playlists.length,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.s12),
          itemBuilder: (context, index) {
            final pl = discover.playlists[index];
            return _buildHotPlaylist(pl, cs, tt);
          },
        ),
      ));
    }

    if (sections.isEmpty) {
      return const EmptyState(message: '搜索你喜欢的音乐');
    }
    return ListView(children: sections);
  }

  /// 热门推荐歌单卡片
  Widget _buildHotPlaylist(Playlist pl, ColorScheme cs, TextTheme tt) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DiscoverPlaylistPage(playlist: pl)),
      ),
      borderRadius: BorderRadius.circular(AppRadius.s12),
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.s12),
              child: _buildHotCover(pl, cs),
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(pl.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tt.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildHotCover(Playlist pl, ColorScheme cs) {
    final url = pl.coverUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(url,
          width: 120, height: 120, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultHotCover(cs));
    }
    return _defaultHotCover(cs);
  }

  Widget _defaultHotCover(ColorScheme cs) {
    return Container(
      width: 120, height: 120,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.s12),
      ),
      child:
          Icon(Icons.queue_music_rounded, color: cs.onSurfaceVariant, size: 32),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchProvider);
    // 有结果时按来源分组展示 tab（全部 + 各来源）
    final showTabs =
        !state.loading && state.keyword.isNotEmpty && state.groups.isNotEmpty;

    return DefaultTabController(
      length: state.groups.length + 1,
      child: Scaffold(
        appBar: _selectionMode
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: '退出多选',
                  onPressed: _clearSelection,
                ),
                title: Text('已选 ${_selected.length} 首'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.playlist_add_rounded),
                    tooltip: '批量加入歌单',
                    onPressed: () => _addSelectedToPlaylist(state.allResults),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download_rounded),
                    tooltip: '批量下载',
                    onPressed: () => _downloadSelected(state.allResults),
                  ),
                ],
              )
            : AppBar(
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
                bottom: showTabs
                    ? TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: [
                          const Tab(text: '全部'),
                          ...state.groups.map((g) => Tab(text: g.sourceName)),
                        ],
                      )
                    : null,
              ),
        body: state.loading
            ? const Center(child: CircularProgressIndicator())
            : state.keyword.isEmpty
                ? _buildIdle(context)
                : state.allResults.isEmpty
                    ? EmptyState(
                        message: '没有找到 "${state.keyword}" 的结果',
                      )
                    : TabBarView(
                        children: [
                          _buildSongList(context, state.allResults),
                          ...state.groups
                              .map((g) => _buildSongList(context, g.songs)),
                        ],
                      ),
      ),
    );
  }

  /// 歌单曲目列表（搜索结果通用渲染）
  Widget _buildSongList(BuildContext context, List<Song> songs) {
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        final selected = _selected.contains(song.globalKey);

        final tile = SongTile(
          song: song,
          onTap: _selectionMode
              ? () => _toggleSelect(song)
              : () => _onPlaySong(song),
          onLongPress: () => _onLongPress(song),
          onArtistTap: _selectionMode
              ? null
              : (artist) => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ArtistPage(artistName: artist),
                    ),
                  ),
          trailing: _selectionMode
              // 多选：勾选指示
              ? Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DownloadButton(song: song),
                    IconButton(
                      icon: const Icon(Icons.playlist_add_rounded),
                      tooltip: '加入歌单',
                      onPressed: () => _addToPlaylist(song),
                    ),
                  ],
                ),
        );

        // 非多选：左滑快速「加入歌单」（弹回列表项，仅触发动作）
        if (_selectionMode) return tile;
        return Dismissible(
          key: ValueKey('search_dismiss_${song.globalKey}'),
          direction: DismissDirection.endToStart,
          background: Container(
            color: cs.primaryContainer,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: AppSpacing.s24),
            child: Icon(Icons.playlist_add_rounded,
                color: cs.onPrimaryContainer),
          ),
          confirmDismiss: (_) {
            unawaited(_addToPlaylist(song));
            return Future.value(false);
          },
          child: tile,
        );
      },
    );
  }
}
