/// 音乐库（原型 renderLibrary / libraryBody）
///
/// 分段控件：全部 + 每个已启用源 + 已下载。三栏的数据来源都是真实能力：
///   * 全部 = [playlistsProvider]（自建歌单 DAO，真实歌单与歌曲快照）；
///   * src:<来源 id> = 该源真实的 getPlaylistList()（页面内 FutureBuilder 调用，
///     不新增全局 provider）；源歌单没有本地路由，点开用弹层展示它的歌曲
///     （[sourcePlaylistSongsProvider]）；
///   * 已下载 = [downloadTasksProvider] 里 completed 的任务 +
///     [songDaoProvider].searchSongs('') 里 localPath 非空的曲目
///     （本地库里真实带着缓存路径的歌）。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/rows.dart';
import '../components/sheets.dart';
import '../components/surfaces.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../providers/providers.dart';
import '../router.dart';
import '../widgets/page_shell.dart';
import '../widgets/track_actions.dart';

/// 音乐库页
class LibraryPage extends ConsumerStatefulWidget {
  /// 构造音乐库页
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  String _tab = 'all';

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(enabledSourcesProvider);

    // 分栏由真实源表生成：全部 + 每个已启用源 + 已下载
    final options = <(String, String)>[('all', '全部')];
    for (final source in enabled) {
      // 只有声明「在音乐库展示」的源才占分栏（本地音乐/我最喜欢/6U音乐不占）
      if (!source.sourceInfo.showInLibrary) continue;
      final id = source.sourceInfo.id;
      options.add(('src:$id', source.sourceInfo.name));
    }
    options.add(('downloaded', '已下载'));

    // 源被停用后原分栏会失效：回退到「全部」，避免停在空页面上
    final valid = options.any((o) => o.$1 == _tab);
    final tab = valid ? _tab : 'all';

    return PageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHead(
            title: '音乐库',
            sub: '按音乐源分栏浏览歌单，本地文件与在线曲目都在这里。',
          ),
          UiV2Segmented(
            options: options,
            value: tab,
            onChanged: (value) => setState(() => _tab = value),
          ),
          if (tab == 'downloaded')
            const _DownloadedBody()
          else if (tab == 'all' || tab == 'src:local_custom')
            // 「自建歌曲」分栏展示的就是「我的歌单」（同一个 DAO 数据源）
            const _OwnedPlaylistsBody()
          else
            _SourcePlaylistsBody(sourceId: tab.substring(4)),
        ],
      ),
    );
  }
}

/// 「全部」分栏：真实自建歌单
class _OwnedPlaylistsBody extends ConsumerWidget {
  /// 构造分栏
  const _OwnedPlaylistsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final playlists = ref.watch(playlistsProvider);
    final list = playlists.value ?? const <Playlist>[];

    if (playlists.isLoading && list.isEmpty) {
      return UiV2Panel(child: _loadingBox(context));
    }

    final quick = _quickEntries(context, ref);

    if (list.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (quick != null) ...[
            quick,
            const SizedBox(height: UiV2Spacing.s5),
          ],
          UiV2Panel(
            child: UiV2Empty(
          title: '还没有歌单',
          text: '自建歌单会出现在这里；也可以在「全部歌单」页里新建。',
          icon: UiV2Icons.queue,
          actions: UiV2Button(
            label: '新建歌单',
            icon: UiV2Icons.plus,
            variant: UiV2ButtonVariant.primary,
            // 新建表单在「全部歌单」页（UiV2NewPlaylistBody），这里直接跳过去
                onTap: () => ref.read(navProvider.notifier).go('playlists'),
              ),
            ),
          ),
        ],
      );
    }

    final count = list.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (quick != null) ...[
          quick,
          const SizedBox(height: UiV2Spacing.s5),
        ],
        UiV2Section(
          title: '我的歌单（$count 个）',
      linkText: '全部歌单',
      onLinkTap: () => ref.read(navProvider.notifier).go('playlists'),
          child: UiV2CardGrid(
            children: [
              for (final playlist in list)
                _OwnedPlaylistCard(playlist: playlist, fallback: t.surface3),
            ],
          ),
        ),
      ],
    );
  }

  /// 手机档的快捷入口：我喜欢的音乐 / 本地音乐
  ///
  /// 大屏左侧导航里已经有这两项；手机档没有，所以在「全部」分栏里补两个入口。
  Widget? _quickEntries(BuildContext context, WidgetRef ref) {
    if (MediaQuery.sizeOf(context).width >= UiV2Breakpoints.wide) return null;
    final likedCount = ref.watch(favoriteCountProvider);
    final localCount = ref.watch(localTracksProvider).length;
    return UiV2Panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          UiV2ListRow(
            key: const ValueKey('library_liked'),
            label: '我喜欢的音乐',
            hint: '$likedCount 首',
            leading: const UiV2Icon(UiV2Icons.heart, size: 18),
            onTap: () => ref.read(navProvider.notifier).go('liked'),
          ),
          UiV2ListRow(
            key: const ValueKey('library_local'),
            label: '本地音乐',
            hint: '$localCount 首',
            leading: const UiV2Icon(UiV2Icons.folder, size: 18),
            divider: false,
            onTap: () => ref.read(navProvider.notifier).go('local'),
          ),
        ],
      ),
    );
  }
}

/// 自建歌单卡片（封面拼贴来自歌单自己的歌曲快照）
class _OwnedPlaylistCard extends ConsumerWidget {
  /// 歌单
  final Playlist playlist;

  /// 拼贴补位色
  final Color fallback;

  /// 构造卡片
  const _OwnedPlaylistCard({required this.playlist, required this.fallback});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final covers = playlist.songKeys
        .map((key) => playlist.songSnapshots[key]?.coverUrl ?? '')
        .where((url) => url.isNotEmpty)
        .take(4)
        .toList();
    final count = playlist.songKeys.length;

    return UiV2PlaylistCard(
      playlist: playlist,
      covers: covers,
      fallback: fallback,
      subtitle: '$count 首',
      width: double.infinity,
      owned: true,
      onTap: () => ref.read(navProvider.notifier).go('playlist', playlist.id),
      onPlay: () => _play(context, ref),
    );
  }

  /// 播放整个歌单：曲目来自快照优先的 playlistSongsProvider
  Future<void> _play(BuildContext context, WidgetRef ref) async {
    final songs = await ref.read(playlistSongsProvider(playlist.id).future);
    if (!context.mounted) return;
    if (songs.isEmpty) {
      showUiV2Toast(context, '这个歌单还没有歌曲');
      return;
    }
    await TrackActions.playAll(context, ref, songs);
  }
}

/// 指定来源分栏：直接向源要歌单列表（真实 getPlaylistList）
class _SourcePlaylistsBody extends ConsumerStatefulWidget {
  /// 源 id
  final String sourceId;

  /// 构造分栏
  const _SourcePlaylistsBody({required this.sourceId});

  @override
  ConsumerState<_SourcePlaylistsBody> createState() =>
      _SourcePlaylistsBodyState();
}

class _SourcePlaylistsBodyState extends ConsumerState<_SourcePlaylistsBody> {
  /// 当前源的歌单请求；必须在 State 里缓存，否则每次 build 都会重新发请求
  late Future<List<Playlist>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(_SourcePlaylistsBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换源时重新请求，避免沿用上一个源的歌单
    if (oldWidget.sourceId != widget.sourceId) _future = _load();
  }

  /// 页面内直接调用源能力（不改 providers.dart：这里只需要一次性结果）
  Future<List<Playlist>> _load() async {
    final source = ref.read(sourceManagerProvider).getSource(widget.sourceId);
    if (source == null) return const <Playlist>[];
    try {
      return await source.getPlaylistList();
    } catch (_) {
      // 单源失败按空处理：页面给出空状态与引导，不静默造假数据
      return const <Playlist>[];
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final source = ref.watch(sourceManagerProvider).getSource(widget.sourceId);
    final sourceName = source?.sourceInfo.name ?? widget.sourceId;

    return FutureBuilder<List<Playlist>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return UiV2Panel(child: _loadingBox(context));
        }
        final lists = snapshot.data ?? const <Playlist>[];
        if (lists.isEmpty) {
          return UiV2Panel(
            child: UiV2Empty(
              title: '「$sourceName」下还没有歌单',
              text: '这个来源暂时没有歌单；也可以去「音乐源」启用别的源。',
              icon: UiV2Icons.queue,
              actions: UiV2Button(
                label: '管理音乐源',
                variant: UiV2ButtonVariant.soft,
                onTap: () => ref.read(navProvider.notifier).go('sources'),
              ),
            ),
          );
        }
        final count = lists.length;
        return UiV2Section(
          title: '$sourceName · $count 个歌单',
          linkText: '全部歌单',
          onLinkTap: () => ref.read(navProvider.notifier).go('playlists'),
          child: UiV2CardGrid(
            children: [
              for (final playlist in lists)
                _SourcePlaylistCard(
                  playlist: playlist,
                  sourceName: sourceName,
                  fallback: t.surface3,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 源歌单卡片（点开进弹层；源歌单没有本地路由）
class _SourcePlaylistCard extends ConsumerWidget {
  /// 源返回的歌单
  final Playlist playlist;

  /// 来源展示名
  final String sourceName;

  /// 拼贴补位色
  final Color fallback;

  /// 构造卡片
  const _SourcePlaylistCard({
    required this.playlist,
    required this.sourceName,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 源歌单也带歌曲快照（CatalogMusicSource 会填），直接取前 4 首封面
    final covers = playlist.songKeys
        .map((key) => playlist.songSnapshots[key]?.coverUrl ?? '')
        .where((url) => url.isNotEmpty)
        .take(4)
        .toList();
    final count = playlist.songKeys.length;

    return UiV2PlaylistCard(
      playlist: playlist,
      covers: covers,
      fallback: fallback,
      subtitle: '$count 首 · $sourceName',
      width: double.infinity,
      onTap: () => _open(context),
      onPlay: () => _play(context, ref),
    );
  }

  /// 源歌单详情：弹层里展示源返回的歌曲
  Future<void> _open(BuildContext context) {
    return showUiV2Sheet(
      context,
      title: playlist.name,
      child: _SourcePlaylistSongsBody(
        sourceId: playlist.sourceId ?? '',
        playlistId: playlist.id,
      ),
    );
  }

  /// 播放源歌单：真实曲目来自 sourcePlaylistSongsProvider
  Future<void> _play(BuildContext context, WidgetRef ref) async {
    final key = (sourceId: playlist.sourceId ?? '', playlistId: playlist.id);
    final songs = await ref.read(sourcePlaylistSongsProvider(key).future);
    if (!context.mounted) return;
    if (songs.isEmpty) {
      showUiV2Toast(context, '这个歌单暂时没有曲目');
      return;
    }
    await TrackActions.playAll(context, ref, songs);
  }
}

/// 源歌单内容（弹层）：歌曲列表 + 播放全部
class _SourcePlaylistSongsBody extends ConsumerWidget {
  /// 源 id
  final String sourceId;

  /// 源歌单 id
  final String playlistId;

  /// 构造内容
  const _SourcePlaylistSongsBody({
    required this.sourceId,
    required this.playlistId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final meta = ref.watch(catalogTracksProvider);
    final songs = ref.watch(
      sourcePlaylistSongsProvider((sourceId: sourceId, playlistId: playlistId)),
    );

    return songs.when(
      loading: () => _loadingBox(context),
      error: (Object error, StackTrace stack) => UiV2Empty(
        title: '歌单读取失败',
        text: '$error',
        icon: UiV2Icons.info,
      ),
      data: (List<Song> list) {
        if (list.isEmpty) {
          return const UiV2Empty(
            title: '这个歌单暂时没有曲目',
            text: '源没有返回曲目，稍后再来看看。',
            icon: UiV2Icons.queue,
          );
        }
        final count = list.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: UiV2Spacing.s3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$count 首 · 来自源 $sourceId',
                      style: UiV2Text.hint.copyWith(color: t.textDim),
                    ),
                  ),
                  UiV2Button(
                    label: '播放全部',
                    icon: UiV2Icons.play,
                    variant: UiV2ButtonVariant.soft,
                    compact: true,
                    onTap: () => TrackActions.playAll(context, ref, list),
                  ),
                ],
              ),
            ),
            UiV2TrackList(
              rows: [
                for (var i = 0; i < list.length; i++)
                  UiV2SongRow(
                    song: list[i],
                    meta: meta[list[i].id],
                    index: i,
                    showArt: true,
                    onTap: () => TrackActions.playAt(context, ref, list, i),
                    onToggleLike: () =>
                        TrackActions.toggleLike(context, ref, list[i]),
                    onMore: () =>
                        showTrackMenu(context, song: list[i]),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// 「已下载」分栏：本地缓存里真实存在的曲目 + 已完成下载任务
class _DownloadedBody extends ConsumerStatefulWidget {
  /// 构造分栏
  const _DownloadedBody();

  @override
  ConsumerState<_DownloadedBody> createState() => _DownloadedBodyState();
}

class _DownloadedBodyState extends ConsumerState<_DownloadedBody> {
  late Future<List<Song>> _localFuture;

  @override
  void initState() {
    super.initState();
    _localFuture = _loadLocal();
  }

  /// 本地库里带着 localPath 的曲目（真实缓存文件；没有 localPath 的不算已下载）
  Future<List<Song>> _loadLocal() async {
    try {
      final all = await ref.read(songDaoProvider).searchSongs('');
      return all.where((song) => (song.localPath ?? '').isNotEmpty).toList();
    } catch (_) {
      return const <Song>[];
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final meta = ref.watch(catalogTracksProvider);
    final tasks =
        ref.watch(downloadTasksProvider).value ?? const <DownloadTask>[];
    final completed = tasks
        .where((task) => task.status == DownloadStatus.completed)
        .toList();

    return FutureBuilder<List<Song>>(
      future: _localFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return UiV2Panel(child: _loadingBox(context));
        }
        final local = snapshot.data ?? const <Song>[];

        if (local.isEmpty && completed.isEmpty) {
          return UiV2Panel(
            child: UiV2Empty(
              title: '还没有已下载的歌曲',
              text: '在歌曲菜单里点下载，完成的曲目会列在这里。',
              icon: UiV2Icons.download,
              actions: UiV2Button(
                label: '查看下载任务',
                variant: UiV2ButtonVariant.soft,
                onTap: () => ref.read(navProvider.notifier).go('downloads'),
              ),
            ),
          );
        }

        // 按专辑名分组（本地文件没有专辑 id，用专辑名作为分组键与展示名）
        final groups = <String, List<Song>>{};
        for (final song in local) {
          final album = (song.album ?? '').isEmpty ? '未知专辑' : song.album!;
          groups.putIfAbsent(album, () => <Song>[]).add(song);
        }
        final albums = groups.entries.map((entry) {
          String? cover;
          for (final song in entry.value) {
            if ((song.coverUrl ?? '').isNotEmpty) {
              cover = song.coverUrl;
              break;
            }
          }
          return Album(
            id: entry.key,
            sourceId: entry.value.first.sourceId,
            title: entry.key,
            artist: entry.value.first.artist,
            coverUrl: cover,
            songs: entry.value,
            songCount: entry.value.length,
          );
        }).toList()
          ..sort((a, b) => a.title.compareTo(b.title));

        // 已完成任务里不在本地库中的部分：如实提示，不猜它的歌名
        final localKeys = local.map((song) => song.globalKey).toSet();
        final unmatched = completed
            .where((task) => !localKeys.contains(task.songKey))
            .toList();

        final albumCount = albums.length;
        final songCount = local.length;
        final unmatchedCount = unmatched.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (albums.isNotEmpty)
              UiV2Section(
                title: '已下载专辑（$albumCount）',
                linkText: '下载任务',
                onLinkTap: () => ref.read(navProvider.notifier).go('downloads'),
                child: UiV2CardGrid(
                  children: [
                    for (final album in albums)
                      UiV2AlbumCard(
                        album: album,
                        width: double.infinity,
                        // 下载视图没有专辑详情入口：点卡片直接播这一组
                        onTap: () =>
                            TrackActions.playAll(context, ref, album.songs),
                        onPlay: () =>
                            TrackActions.playAll(context, ref, album.songs),
                      ),
                  ],
                ),
              ),
            if (local.isNotEmpty)
              UiV2Section(
                title: '已下载曲目（$songCount）',
                child: UiV2Panel(
                  child: UiV2TrackList(
                    rows: [
                      for (var i = 0; i < local.length; i++)
                        UiV2SongRow(
                          song: local[i],
                          meta: meta[local[i].id],
                          index: i,
                          showArt: true,
                          onTap: () =>
                              TrackActions.playAt(context, ref, local, i),
                          onToggleLike: () =>
                              TrackActions.toggleLike(context, ref, local[i]),
                          onMore: () => showTrackMenu(
                            context,
                            trackId: local[i].globalKey,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (unmatchedCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: UiV2Spacing.s2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '另有 $unmatchedCount 个已完成任务不在本地库里',
                        style: UiV2Text.hint.copyWith(color: t.textDim),
                      ),
                    ),
                    UiV2GhostMini(
                      label: '查看下载任务',
                      onTap: () =>
                          ref.read(navProvider.notifier).go('downloads'),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 面板内的加载态（与原列表高度相近，避免布局跳动）
Widget _loadingBox(BuildContext context) {
  final t = UiV2Theme.of(context);
  return Padding(
    padding: const EdgeInsets.all(UiV2Spacing.s8),
    child: Center(child: UiV2Spinner(trackColor: t.surface3, color: t.accent)),
  );
}
