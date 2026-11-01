/// 艺人详情（原型 renderArtist）
///
/// 数据来源：演示曲库源（[CatalogMusicSource]）的艺人派生表 —— 与真实源
/// `getArtist(name)` 同一份数据；按名字过滤源曲目作为兜底（本地扫描 /
/// 规则源的曲目只有 artist 字段，没有艺人实体）。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/hero.dart';
import '../components/rows.dart';
import '../components/sheets.dart';
import '../components/surfaces.dart';
import '../data/catalog.dart';
import '../data/catalog_source.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../providers/providers.dart';
import '../router.dart';
import '../widgets/page_shell.dart';
import '../widgets/track_actions.dart';

/// 艺人详情页
class ArtistPage extends ConsumerWidget {
  /// 艺人名（与原型一致，用名字而不是 id）
  final String artistName;

  /// 构造页面
  const ArtistPage({super.key, required this.artistName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(catalogSourceProvider);
    final metas = ref.watch(catalogTracksProvider);

    // 艺人实体来自源自己的派生表；取不到时退到「按 artist 字段过滤源曲目」
    final artist = source.catalog.artists
        .where((item) => item.name == artistName)
        .firstOrNull;
    final songs = artist != null
        ? artist.tracks.map(source.songOf).toList(growable: false)
        : source.allSongs
            .where((song) => song.artist == artistName)
            .toList(growable: false);

    if (songs.isEmpty) {
      return PageShell(
        child: UiV2Panel(
          child: UiV2Empty(
            title: '没有找到这位艺人',
            text: '链接可能已失效，回到搜索继续浏览。',
            icon: UiV2Icons.info,
            actions: UiV2Button(
              label: '回到搜索',
              variant: UiV2ButtonVariant.primary,
              onTap: () => ref.read(navProvider.notifier).go('search'),
            ),
          ),
        ),
      );
    }

    final name = artist?.name ?? artistName;
    // 专辑卡片只认 core 的 Album，用源自身的曲目映射组装，不做类型强转
    final albums = [
      for (final item in artist?.albums ?? const <CatalogAlbum>[])
        _coreAlbumOf(source, item),
    ];
    final hot = songs.take(8).toList(growable: false);
    final cover = albums.isNotEmpty
        ? albums.first.coverUrl
        : (resolveSongCover(ref, songs.first) ?? songs.first.coverUrl);

    return PageShell(
      topPadding: UiV2Spacing.s4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiV2Hero(
            art: UiV2Cover(source: cover, size: double.infinity, radius: 0),
            type: '艺人',
            title: name,
            meta: '${albums.length} 张专辑 · ${songs.length} 首歌',
            actions: [
              UiV2Button(
                label: '播放热门',
                icon: UiV2Icons.play,
                variant: UiV2ButtonVariant.primary,
                onTap: () => TrackActions.playAll(context, ref, songs),
              ),
            ],
          ),
          if (albums.isNotEmpty)
            UiV2Section(
              title: '专辑',
              child: UiV2CardGrid(
                children: [
                  for (final album in albums)
                    UiV2AlbumCard(
                      album: album,
                      width: double.infinity,
                      onTap: () => ref
                          .read(navProvider.notifier)
                          .go('album', album.id),
                      onPlay: () =>
                          TrackActions.playAll(context, ref, album.songs),
                    ),
                ],
              ),
            ),
          UiV2Section(
            title: '热门歌曲',
            child: UiV2Panel(
              child: UiV2TrackList(
                rows: [
                  for (var i = 0; i < hot.length; i++)
                    UiV2SongRow(
                      song: hot[i],
                      meta: metas[hot[i].id],
                      index: i,
                      showArt: true,
                      onTap: () => TrackActions.playAt(context, ref, hot, i),
                      onToggleLike: () =>
                          TrackActions.toggleLike(context, ref, hot[i]),
                      onMore: () =>
                          showTrackMenu(context, song: hot[i]),
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

/// 把演示曲库的专辑派生成 core 的 [Album]
///
/// 本页只用它给卡片与播放入口供数：卡片组件不接受 CatalogAlbum。
Album _coreAlbumOf(CatalogMusicSource source, CatalogAlbum album) => Album(
      id: album.id,
      sourceId: source.sourceInfo.id,
      title: album.title,
      artist: album.artist,
      coverUrl: album.cover,
      songCount: album.tracks.length,
      songs: album.tracks.map(source.songOf).toList(growable: false),
      extra: {
        'year': album.year,
        'genre': album.genre,
      },
    );
