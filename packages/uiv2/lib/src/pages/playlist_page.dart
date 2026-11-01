/// 歌单详情（原型 renderPlaylist）
///
/// 数据来源：自建歌单的真实 DAO（[playlistByIdProvider] + [playlistSongsProvider]，
/// 曲目直接来自写入时保存的快照）。工具行（添加歌曲 / 重命名 / 删除歌单）全部
/// 走 [PlaylistActions] 的真实写操作。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/hero.dart';
import '../components/rows.dart';
import '../components/sheets.dart';
import '../components/surfaces.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../providers/providers.dart';
import '../router.dart';
import '../widgets/page_shell.dart';
import '../widgets/track_actions.dart';

/// 歌单详情页
class PlaylistPage extends ConsumerWidget {
  /// 歌单 id
  final String playlistId;

  /// 构造页面
  const PlaylistPage({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPlaylist = ref.watch(playlistByIdProvider(playlistId));

    return asyncPlaylist.when(
      // 首次读库期间给占位，避免先把「不存在」闪出来
      loading: () => const _PlaylistLoadingShell(),
      error: (_, __) => const _PlaylistMissingShell(),
      data: (playlist) => playlist == null
          ? const _PlaylistMissingShell()
          : _PlaylistBody(playlist: playlist),
    );
  }
}

/// 歌单主体（拿到 [Playlist] 后才有意义）
class _PlaylistBody extends ConsumerWidget {
  /// 歌单
  final Playlist playlist;

  /// 构造主体
  const _PlaylistBody({required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    // 快照直出；旧数据缺快照时由 songsOf 回源补齐（失败的那首会被跳过）
    final songs =
        ref.watch(playlistSongsProvider(playlist.id)).value ?? const <Song>[];
    final totalSec =
        songs.fold<int>(0, (sum, song) => sum + (song.duration ?? 0));
    // 没有来源标记的歌单就是本机自建的，可以改名/删除/增删曲目
    final mine = (playlist.sourceId ?? '').isEmpty;
    final covers =
        songs.take(4).map((song) => song.coverUrl ?? '').toList(growable: false);
    final otherPlaylists =
        (ref.watch(playlistsProvider).value ?? const <Playlist>[])
            .where((item) => item.id != playlist.id)
            .take(6)
            .toList(growable: false);

    return PageShell(
      topPadding: UiV2Spacing.s4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiV2Hero(
            art: UiV2Mosaic(
              covers: covers,
              fallback: t.accentSoft2,
              radius: 16,
            ),
            type: '歌单${mine ? ' · 我的' : ' · 来源歌单'}',
            title: playlist.name,
            meta: '${songs.length} 首 · ${(totalSec / 60).round()} 分钟 · 更新于 ${_formatDate(playlist.modifiedTime)}',
            actions: [
              UiV2Button(
                label: '播放',
                icon: UiV2Icons.play,
                variant: UiV2ButtonVariant.primary,
                onTap: () => TrackActions.playAll(context, ref, songs),
              ),
              UiV2Button(
                label: '随机播放',
                icon: UiV2Icons.shuffle,
                variant: UiV2ButtonVariant.soft,
                onTap: () => TrackActions.shuffleAll(context, ref, songs),
              ),
              if (songs.isNotEmpty)
                UiV2Button(
                  label: '加入队列',
                  icon: UiV2Icons.queue,
                  variant: UiV2ButtonVariant.outline,
                  onTap: () {
                    final added = TrackActions.addAllToQueue(ref, songs);
                    showUiV2Toast(
                      context,
                      added > 0 ? '已加入 $added 首到播放队列' : '这些歌曲已经在队列里了',
                    );
                  },
                ),
              UiV2IconButton(
                icon: UiV2Icons.more,
                semanticLabel: '更多歌单操作',
                onTap: () => showUiV2Toast(
                  context,
                  mine ? '自建歌单可重命名或删除' : '来源歌单不支持在此编辑',
                  info: !mine,
                ),
              ),
            ],
          ),
          if (mine)
            Padding(
              padding: const EdgeInsets.only(bottom: UiV2Spacing.s4),
              child: Wrap(
                spacing: UiV2Spacing.s2,
                runSpacing: UiV2Spacing.s2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  UiV2Button(
                    label: '添加歌曲',
                    icon: UiV2Icons.plus,
                    variant: UiV2ButtonVariant.soft,
                    compact: true,
                    onTap: () => showUiV2Sheet(
                      context,
                      title: '管理歌曲 · ${playlist.name}',
                      child: UiV2PlaylistPickerBody(playlistId: playlist.id),
                    ),
                  ),
                  UiV2GhostMini(
                    label: '重命名',
                    icon: UiV2Icons.edit,
                    onTap: () => showUiV2Sheet(
                      context,
                      title: '重命名歌单',
                      child: UiV2RenamePlaylistBody(playlist: playlist),
                    ),
                  ),
                  UiV2GhostMini(
                    label: '删除歌单',
                    icon: UiV2Icons.trash,
                    danger: true,
                    onTap: () => showConfirmSheet(
                      context,
                      title: '删除歌单',
                      text: '删除后无法恢复，「${playlist.name}」里的歌曲仍保留在音乐库中。',
                      confirmLabel: '删除歌单',
                      onConfirm: () async {
                        await ref
                            .read(playlistActionsProvider)
                            .delete(playlist.id);
                        // 删除后组件可能已经卸载，用 ref/context 之前先确认还挂着
                        if (!context.mounted) return;
                        ref.read(navProvider.notifier).go('playlists');
                        showUiV2Toast(context, '已删除「${playlist.name}」');
                      },
                    ),
                  ),
                ],
              ),
            ),
          UiV2Panel(
            child: songs.isEmpty
                ? UiV2Empty(
                    title: mine ? '这个歌单还没有歌曲' : '这个歌单暂时没有曲目',
                    text: mine ? '点「添加歌曲」，从音乐库里挑几首放进来。' : '稍后再来看看。',
                    icon: UiV2Icons.queue,
                    actions: mine
                        ? UiV2Button(
                            label: '添加歌曲',
                            icon: UiV2Icons.plus,
                            variant: UiV2ButtonVariant.primary,
                            onTap: () => showUiV2Sheet(
                              context,
                              title: '管理歌曲 · ${playlist.name}',
                              child: UiV2PlaylistPickerBody(
                                playlistId: playlist.id,
                              ),
                            ),
                          )
                        : null,
                  )
                : UiV2TrackList(
                    rows: [
                      for (var i = 0; i < songs.length; i++)
                        UiV2SongRow(
                          song: songs[i],
                          meta: ref.watch(catalogTracksProvider)[songs[i].id],
                          index: i,
                          showArt: true,
                          onTap: () =>
                              TrackActions.playAt(context, ref, songs, i),
                          onToggleLike: () =>
                              TrackActions.toggleLike(context, ref, songs[i]),
                          onMore: () => showTrackMenu(
                            context,
                            song: songs[i],
                            onRemove: () async {
                              await ref
                                  .read(playlistActionsProvider)
                                  .removeSong(playlist.id, songs[i].globalKey);
                              if (!context.mounted) return;
                              showUiV2Toast(
                                context,
                                '已从「${playlist.name}」移除「${songs[i].title}」',
                              );
                            },
                          ),
                        ),
                    ],
                  ),
          ),
          if (otherPlaylists.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: UiV2Spacing.s6),
              child: UiV2Section(
                title: mine ? '其他歌单' : '相似歌单',
                child: UiV2Rail(
                  children: [
                    for (final other in otherPlaylists)
                      UiV2PlaylistCard(
                        playlist: other,
                        covers: _coversOf(other),
                        subtitle: _subtitleOf(other),
                        owned: (other.sourceId ?? '').isEmpty,
                        onTap: () => ref
                            .read(navProvider.notifier)
                            .go('playlist', other.id),
                        onPlay: () => _playPlaylist(context, ref, other),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 歌单不存在「或」读库失败时的引导页
class _PlaylistMissingShell extends ConsumerWidget {
  /// 构造引导页
  const _PlaylistMissingShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PageShell(
      child: UiV2Panel(
        child: UiV2Empty(
          title: '这个歌单不存在或已被删除',
          text: '链接可能已失效，回到音乐库继续浏览。',
          icon: UiV2Icons.info,
          actions: UiV2Button(
            label: '回到音乐库',
            variant: UiV2ButtonVariant.primary,
            onTap: () => ref.read(navProvider.notifier).go('library'),
          ),
        ),
      ),
    );
  }
}

/// 首次读库时的占位
class _PlaylistLoadingShell extends StatelessWidget {
  /// 构造占位
  const _PlaylistLoadingShell();

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return PageShell(
      child: UiV2Panel(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: UiV2Spacing.s8),
          child: Center(
            child: UiV2Spinner(trackColor: t.lineStrong, color: t.accent),
          ),
        ),
      ),
    );
  }
}

/// 歌单选曲弹层（.pick 行：点一下加入 / 移出）
///
/// 候选 = 演示曲库源的曲目 + 本地扫描曲目（按全局键去重）；点一下立即写库并
/// 提示，选中态直接看歌单的 songKeys —— 写库后 provider 失效，这一层会重建。
class UiV2PlaylistPickerBody extends ConsumerWidget {
  /// 目标歌单 id
  final String playlistId;

  /// 构造内容
  const UiV2PlaylistPickerBody({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final playlist = ref.watch(playlistByIdProvider(playlistId)).value;
    if (playlist == null) {
      return const UiV2Empty(title: '歌单不存在', icon: UiV2Icons.info);
    }

    final metas = ref.watch(catalogTracksProvider);
    // 去重：演示曲库与本地扫描的全局键不会撞车，但插件源可能存在同键曲目
    final seen = <String>{};
    final candidates = <Song>[];
    for (final song in [
      ...ref.watch(catalogSourceProvider).allSongs,
      ...ref.watch(localTracksProvider),
    ]) {
      if (seen.add(song.globalKey)) candidates.add(song);
    }

    if (candidates.isEmpty) {
      return const UiV2Empty(
        title: '曲库是空的',
        text: '先在「音乐源」页启用一个源，或在本地音乐里扫描一个文件夹。',
        icon: UiV2Icons.queue,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '点一下即可加入或移出，改动会立即保存。',
          style: UiV2Text.hint.copyWith(color: t.textDim),
        ),
        const SizedBox(height: UiV2Spacing.s3),
        for (final song in candidates)
          UiV2Pressable(
            onTap: () => _toggle(context, ref, playlist, song),
            radius: UiV2Radii.brMd,
            hoverColor: t.surface2,
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: UiV2Spacing.s2),
              child: Row(
                children: [
                  UiV2Cover(
                    source: metas[song.id]?.cover ?? song.coverUrl,
                    size: 40,
                  ),
                  const SizedBox(width: UiV2Spacing.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          song.title,
                          style: UiV2Text.trackTitle.copyWith(color: t.text),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          [
                            song.artist,
                            song.album ?? '',
                          ].where((part) => part.isNotEmpty).join(' · '),
                          style: UiV2Text.hint.copyWith(color: t.textDim),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: UiV2Spacing.s2),
                  _PickMark(
                    selected: playlist.songKeys.contains(song.globalKey),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 点一下：已在歌单里就移出，否则加入；结果如实提示
  static Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
    Song song,
  ) async {
    final actions = ref.read(playlistActionsProvider);
    final inside = playlist.songKeys.contains(song.globalKey);
    if (inside) {
      await actions.removeSong(playlist.id, song.globalKey);
    } else {
      await actions.addSong(playlist.id, song);
    }
    if (!context.mounted) return;
    showUiV2Toast(
      context,
      inside ? '已从「${playlist.name}」移除' : '已加入「${playlist.name}」',
    );
  }
}

/// 选曲行尾的勾选圆点
class _PickMark extends StatelessWidget {
  /// 是否已在歌单里
  final bool selected;

  /// 构造圆点
  const _PickMark({required this.selected});

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: selected ? t.accent : const Color(0x00000000),
        border: Border.all(color: selected ? t.accent : t.lineStrong),
        borderRadius: UiV2Radii.brPill,
      ),
      alignment: Alignment.center,
      child: UiV2Icon(
        selected ? UiV2Icons.check : UiV2Icons.plus,
        size: 16,
        color: selected ? t.accentInk : t.textMute,
      ),
    );
  }
}

/// 重命名歌单弹层内容（真实写回 DAO）
class UiV2RenamePlaylistBody extends ConsumerStatefulWidget {
  /// 目标歌单
  final Playlist playlist;

  /// 构造内容
  const UiV2RenamePlaylistBody({super.key, required this.playlist});

  @override
  ConsumerState<UiV2RenamePlaylistBody> createState() =>
      _UiV2RenamePlaylistBodyState();
}

class _UiV2RenamePlaylistBodyState
    extends ConsumerState<UiV2RenamePlaylistBody> {
  late final TextEditingController _name =
      TextEditingController(text: widget.playlist.name);
  String? _error;

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
          label: '保存',
          variant: UiV2ButtonVariant.primary,
          block: true,
          onTap: () async {
            final name = _name.text.trim();
            if (name.isEmpty) {
              setState(() => _error = '请输入歌单名称');
              return;
            }
            await ref
                .read(playlistActionsProvider)
                .rename(widget.playlist.id, name);
            if (!mounted) return;
            // 先弹提示再关闭弹层：弹层关闭后 context 就不能再用了
            showUiV2Toast(context, '已重命名为「$name」');
            Navigator.of(context).maybePop();
          },
        ),
      ],
    );
  }
}

/// 播放某个自建歌单（快照优先，缺快照的曲目回源补齐）
Future<void> _playPlaylist(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final songs = await ref.read(playlistActionsProvider).songsOf(playlist);
  if (!context.mounted) return;
  if (songs.isEmpty) {
    showUiV2Toast(context, '「${playlist.name}」还没有歌曲', info: true);
    return;
  }
  await TrackActions.playAll(context, ref, songs);
}

/// 歌单封面：写入时保存的前 4 首快照的封面（不足 4 首由拼贴补齐占位色）
List<String> _coversOf(Playlist playlist) => playlist.songSnapshots.values
    .take(4)
    .map((song) => song.coverUrl ?? '')
    .toList(growable: false);

/// 歌单副标题：首数 + 更新时间
String _subtitleOf(Playlist playlist) =>
    '${playlist.songKeys.length} 首 · ${_formatDate(playlist.modifiedTime)}';

/// 日期 → `yyyy-MM-dd`（歌单元信息用，避免为此引入 intl 依赖）
String _formatDate(DateTime time) {
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  return '${time.year}-$month-$day';
}
