/// 首页（原型 renderHome）—— 三块：最近播放、推荐歌曲、我的歌单。
///
/// 数据来源全部换成真实能力，配表（[CatalogTrack]）只作为**展示元数据**
/// （封面 / 时长）参与渲染：
///   * 最近播放 = [recentSongsProvider]（RecentPlaysService 的真实快照）；
///   * 推荐歌曲 = [recommendedPlaylistsProvider] 聚合到的源歌单 → 该歌单的歌曲
///     （[sourcePlaylistSongsProvider]）；没有可用真实推荐时**整块隐藏**，
///     不再拿演示曲库顶位（那等于假装有推荐）；
///   * 我的歌单 = [playlistsProvider]（自建歌单 DAO），新建走 [playlistActionsProvider]。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/rows.dart';
import '../components/sheets.dart';
import '../components/surfaces.dart';
import '../data/catalog.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../providers/providers.dart';
import '../router.dart';
import '../widgets/page_shell.dart';
import '../widgets/track_actions.dart';

/// 首页
class HomePage extends ConsumerWidget {
  /// 构造首页
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 最近播放：真实服务快照（title/artist/cover 都在记录里，不需要回源）
    final recent = ref.watch(recentSongsProvider);
    // 展示元数据（配表曲目）只用来补封面与时长
    final meta = ref.watch(catalogTracksProvider);
    // 顶部副标题的「已启用 N 个音乐源」必须来自真实源表
    final srcOn = ref.watch(enabledSourcesProvider).length;

    return PageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(
            title: '下午好，今天想听点什么？',
            sub: srcOn > 0
                ? '已启用 $srcOn 个音乐源 · 手机与大屏同一套界面。'
                : '所有音乐源都已停用，去「音乐源」重新打开一个。',
            action: UiV2Button(
              label: '搜索歌曲',
              icon: UiV2Icons.search,
              variant: UiV2ButtonVariant.soft,
              onTap: () => ref.read(navProvider.notifier).go('search'),
            ),
          ),
          UiV2Section(
            title: '最近播放',
            linkText: recent.isEmpty ? null : '查看全部',
            onLinkTap: () => ref.read(navProvider.notifier).go('recent'),
            child: recent.isEmpty
                ? UiV2Panel(
                    child: UiV2Empty(
                      title: '还没有最近播放',
                      text: '点开任意一首歌，它会自动出现在这里。',
                      icon: UiV2Icons.clock,
                      actions: UiV2Button(
                        label: '去找首歌',
                        variant: UiV2ButtonVariant.primary,
                        onTap: () => ref.read(navProvider.notifier).go('search'),
                      ),
                    ),
                  )
                : UiV2Rail(
                    children: [
                      for (final song in recent.take(8))
                        _RecentCard(song: song, meta: meta[song.id]),
                    ],
                  ),
          ),
          const _RecommendedSection(),
          const _MyPlaylistsSection(),
        ],
      ),
    );
  }
}

/// 最近播放卡片（原型的 .card + .card__art）
///
/// 外观沿用原型（236 宽卡片 + 悬浮播放浮标），只是曲目换成真实 [Song]，
/// 专辑信息来自可空的展示元数据。
class _RecentCard extends ConsumerWidget {
  /// 曲目（真实 Song 快照）
  final Song song;

  /// 展示元数据（配表曲目，可为空）
  final CatalogTrack? meta;

  /// 构造卡片
  const _RecentCard({required this.song, this.meta});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = resolveSongCover(ref, song, catalogCover: meta?.cover);
    // 单曲入口：进最近播放队列（专辑页已移除，卡片点击就是播放）
    // 显式标注成 VoidCallback：返回值（Future）会被丢弃
    final VoidCallback onCardTap =
        () => TrackActions.playAsRecent(context, ref, song);
    final title = song.title.isEmpty ? '（未知曲目）' : song.title;

    return UiV2CardShell(
      width: 236,
      art: UiV2CardArt(
        child: UiV2Cover(source: cover, size: double.infinity),
        onTap: onCardTap,
        onPlay: () => TrackActions.playAsRecent(context, ref, song),
        playLabel: '播放：$title',
        semanticLabel: [song.album ?? '', song.artist]
            .where((s) => s.isNotEmpty)
            .join('，'),
      ),
      title: title,
      meta: [song.artist],
      onTap: onCardTap,
    );
  }
}

/// 推荐歌曲区块
///
/// 数据链路：已启用源的真实推荐歌单 → 选中歌单的歌曲；
/// 没有可用推荐源时退回「演示曲库」源的前 8 首，并在副标题里写明来源。
class _RecommendedSection extends ConsumerWidget {
  /// 构造区块
  const _RecommendedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(recommendedPlaylistsProvider);

    // 没有**真实**推荐就整块不显示（连标题一起）：
    // 拿演示曲库的 8 首来顶位是"假装有推荐"，用户明确要求不要。
    // 加载中/失败/空列表/歌单里没歌 —— 一律隐藏。
    final list = playlists.value;
    final pick = list == null ? null : pickRecommendedPlaylist(list);
    // 选中歌单的真实曲目：以 (来源 id, 歌单 id) 向源请求
    final songsOfPicked = pick == null
        ? null
        : ref
            .watch(sourcePlaylistSongsProvider((
              sourceId: pick.sourceId ?? '',
              playlistId: pick.id,
            )))
            .value;
    final songs = pickRecommendedSongs(
      playlists: list,
      songsOfPicked: songsOfPicked,
    );
    if (songs.isEmpty) return const SizedBox.shrink();

    return UiV2Section(
      title: '推荐歌曲',
      child: UiV2Panel(
        child: _songList(
          context,
          ref,
          songs,
          note: '来自歌单「${pick!.name}」',
        ),
      ),
    );
  }
}

/// 我的歌单区块（真实自建歌单 DAO）
class _MyPlaylistsSection extends ConsumerWidget {
  /// 构造区块
  const _MyPlaylistsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 「我的歌单」只列自建歌单（收藏的远端歌单在音乐库「收藏歌单」分栏）
    final playlists = ref.watch(ownedPlaylistsProvider);
    final current = playlists.value ?? const <Playlist>[];

    return UiV2Section(
      title: '我的歌单',
      linkText: current.isEmpty ? null : '全部歌单',
      onLinkTap: () => ref.read(navProvider.notifier).go('playlists'),
      child: playlists.when(
        loading: () => UiV2Panel(child: _loading(context)),
        error: (Object error, StackTrace stack) => UiV2Panel(
          child: UiV2Empty(
            title: '歌单读取失败',
            text: '$error',
            icon: UiV2Icons.info,
            actions: UiV2Button(
              label: '新建歌单',
              icon: UiV2Icons.plus,
              variant: UiV2ButtonVariant.primary,
              onTap: () => _showCreatePlaylist(context),
            ),
          ),
        ),
        data: (List<Playlist> list) => list.isEmpty
            ? UiV2Panel(
                child: UiV2Empty(
                  title: '还没有自建歌单',
                  text: '把喜欢的歌收进一个歌单，方便下次直接播。',
                  icon: UiV2Icons.queue,
                  actions: UiV2Button(
                    label: '新建歌单',
                    icon: UiV2Icons.plus,
                    variant: UiV2ButtonVariant.primary,
                    onTap: () => _showCreatePlaylist(context),
                  ),
                ),
              )
            : UiV2Rail(
                children: [
                  for (final playlist in list.take(8))
                    _OwnedPlaylistCard(playlist: playlist),
                ],
              ),
      ),
    );
  }
}

/// 自建歌单卡片（封面拼贴取自歌单里的真实歌曲快照）
class _OwnedPlaylistCard extends ConsumerWidget {
  /// 歌单
  final Playlist playlist;

  /// 构造卡片
  const _OwnedPlaylistCard({required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    // 写库时保存了歌曲快照：直接取前 4 首的封面拼贴，不用回源
    // 统一实现：避免同一歌单在不同页面出现不同拼贴（见 resolvePlaylistCovers 注释）
    final covers = resolvePlaylistCovers(ref, playlist);
    final count = playlist.songKeys.length;

    return UiV2PlaylistCard(
      playlist: playlist,
      covers: covers,
      fallback: t.surface3,
      subtitle: '$count 首',
      owned: true,
      onTap: () => ref.read(navProvider.notifier).go('playlist', playlist.id),
      onPlay: () => _playPlaylist(context, ref),
    );
  }

  /// 播放整个歌单：曲目走快照优先的 playlistSongsProvider
  Future<void> _playPlaylist(BuildContext context, WidgetRef ref) async {
    final songs = await ref.read(playlistSongsProvider(playlist.id).future);
    if (!context.mounted) return;
    if (songs.isEmpty) {
      showUiV2Toast(context, '这个歌单还没有歌曲');
      return;
    }
    // 卡片的播放键 = 继续播放：有进度接着听，没有就从头（同一入口，不另设按钮）
    await TrackActions.resume(
        context, ref, TrackActions.playlistQueue(playlist, songs));
  }
}

/// 打开「新建歌单」弹层（输入名称 → 真实写入歌单 DAO）
Future<void> _showCreatePlaylist(BuildContext context) {
  return showUiV2Sheet(
    context,
    title: '新建歌单',
    child: const _NewPlaylistBody(),
  );
}

/// 新建歌单表单
///
/// 与「全部歌单」页的表单外观一致，差别是这里真的调用
/// [playlistActionsProvider].create 落库（创建后 playlistsProvider 会被刷新）。
class _NewPlaylistBody extends ConsumerStatefulWidget {
  /// 构造表单
  const _NewPlaylistBody();

  @override
  ConsumerState<_NewPlaylistBody> createState() => _NewPlaylistBodyState();
}

class _NewPlaylistBodyState extends ConsumerState<_NewPlaylistBody> {
  final TextEditingController _name = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('歌单名称', style: UiV2Text.buttonSmall.copyWith(color: t.text)),
        const SizedBox(height: 6),
        TextField(
          controller: _name,
          maxLength: 24,
          autofocus: true,
          style: UiV2Text.body.copyWith(color: t.text),
          decoration: InputDecoration(
            counterText: '',
            hintText: '例如：周末早晨',
            hintStyle: UiV2Text.body.copyWith(color: t.textMute),
            filled: true,
            fillColor: t.surface2,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: UiV2Spacing.s4,
              vertical: UiV2Spacing.s3,
            ),
            border: OutlineInputBorder(
              borderRadius: UiV2Radii.brMd,
              borderSide: BorderSide(color: t.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: UiV2Radii.brMd,
              borderSide: BorderSide(color: t.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: UiV2Radii.brMd,
              borderSide: BorderSide(color: t.accent),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: UiV2Text.hint.copyWith(color: t.accent)),
        ],
        const SizedBox(height: UiV2Spacing.s4),
        UiV2Button(
          label: _saving ? '创建中…' : '创建歌单',
          variant: UiV2ButtonVariant.primary,
          block: true,
          onTap: _saving ? null : _submit,
        ),
      ],
    );
  }

  /// 校验名称后写入 DAO（空名字不落库，避免产生无名歌单）
  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请输入歌单名称');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    await ref.read(playlistActionsProvider).create(name);
    if (!mounted) return;
    // 先弹提示再关弹层：关掉之后本 widget 的 context 可能已经失效
    showUiV2Toast(context, '已创建歌单「$name」');
    Navigator.of(context).maybePop();
  }
}

/// 首页「推荐歌曲」区块的**内容决策**
///
/// 用户要求：没有真实推荐就整块隐藏，**不要**拿演示曲库的曲目顶上（那等于
/// 假装有推荐）。因此这里只在"有真实推荐歌单 + 该歌单确实有曲目"时返回曲目，
/// 其余情况（还在加载 / 读取失败 / 没有推荐 / 歌单为空）一律返回空列表 = 隐藏。
List<Song> pickRecommendedSongs({
  required List<Playlist>? playlists,
  required List<Song>? songsOfPicked,
  int limit = 8,
}) {
  if (playlists == null || playlists.isEmpty) return const [];
  if (pickRecommendedPlaylist(playlists) == null) return const [];
  final songs = songsOfPicked;
  if (songs == null || songs.isEmpty) return const [];
  return songs.take(limit).toList(growable: false);
}

/// 从聚合到的推荐歌单里挑一个首页推荐源
///
/// 优先名字里带「今日 / 推荐 / 每日」的歌单；否则取第一个歌单——
/// 各源的 getPlaylistList 本身就是推荐位，用真实数据比编造推荐更诚实。
/// 列表为空时返回 null，由调用方退回演示曲库。
Playlist? pickRecommendedPlaylist(List<Playlist> playlists) {
  if (playlists.isEmpty) return null;
  const hints = ['今日', '推荐', '每日'];
  for (final playlist in playlists) {
    if (hints.any(playlist.name.contains)) return playlist;
  }
  return playlists.first;
}

/// 推荐曲目列表（统一走 [UiV2SongRow]）
Widget _songList(
  BuildContext context,
  WidgetRef ref,
  List<Song> songs, {
  required String note,
}) {
  final meta = ref.watch(catalogTracksProvider);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sourceNote(context, note),
      UiV2TrackList(
        rows: [
          for (var i = 0; i < songs.length; i++)
            UiV2SongRow(
              song: songs[i],
              meta: meta[songs[i].id],
              index: i,
              showArt: true,
              onTap: () => TrackActions.playAsRecent(context, ref, songs[i]),
              onToggleLike: () =>
                  TrackActions.toggleLike(context, ref, songs[i]),
              onMore: () => showTrackMenu(context, song: songs[i]),
            ),
        ],
      ),
    ],
  );
}

/// 区块内副标题：标注推荐的真实来源（不写来源的推荐等于编数据）
Widget _sourceNote(BuildContext context, String text) {
  final t = UiV2Theme.of(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(
      UiV2Spacing.s4,
      UiV2Spacing.s3,
      UiV2Spacing.s4,
      0,
    ),
    child: Text(text, style: UiV2Text.hint.copyWith(color: t.textDim)),
  );
}

/// 面板内的加载态（保持与原列表相近的高度，避免布局跳动）
Widget _loading(BuildContext context) {
  final t = UiV2Theme.of(context);
  return Padding(
    padding: const EdgeInsets.all(UiV2Spacing.s6),
    child: Center(child: UiV2Spinner(trackColor: t.surface3, color: t.accent)),
  );
}
