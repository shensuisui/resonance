/// 专辑详情（原型 renderAlbum）
///
/// 数据来源：演示曲库源（[CatalogMusicSource]）自己的专辑对象 —— 与真实源
/// `getAlbum(id)` 同一份数据；参数是专辑名时退回「按专辑名在源曲目里过滤」。
/// 配表只用来补展示元数据，不再被当作列表数据源。
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
import '../design/typography.dart';
import '../providers/providers.dart';
import '../router.dart';
import '../widgets/page_shell.dart';
import '../widgets/track_actions.dart';

/// 专辑详情页
class AlbumPage extends ConsumerWidget {
  /// 专辑 id（也可能是专辑名，见 [build] 的兜底分支）
  final String albumId;

  /// 构造页面
  const AlbumPage({super.key, required this.albumId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final source = ref.watch(catalogSourceProvider);
    final metas = ref.watch(catalogTracksProvider);

    // 优先取源自己的专辑对象；这条路径拿到的是源的真实数据，而不是页面遍历配表
    final album = source.catalog.album(albumId);
    // 兜底：参数可能是专辑名（本地扫描/规则源的 album 字段只有名字），按名过滤源曲目
    final songs = album != null
        ? album.tracks.map(source.songOf).toList(growable: false)
        : source.allSongs
            .where((song) => song.album == albumId)
            .toList(growable: false);

    if (songs.isEmpty) {
      return PageShell(
        child: UiV2Panel(
          child: UiV2Empty(
            title: '这张专辑不在库里',
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

    final title = album?.title ?? (songs.first.album ?? albumId);
    final artist = album?.artist ?? songs.first.artist;
    final cover =
        album?.cover ?? resolveSongCover(ref, songs.first) ?? songs.first.coverUrl;
    final year = album?.year;
    final genre = album?.genre;
    final totalSec =
        songs.fold<int>(0, (sum, song) => sum + (song.duration ?? 0));
    // 「本地 / 已下载」优先用源给的元数据；源没给时按曲目真实的 localPath 判断
    final hasLocalFile =
        songs.every((song) => (song.localPath ?? '').isNotEmpty);
    final imported = album?.imported ?? hasLocalFile;
    final downloaded = album?.downloaded ?? hasLocalFile;
    final type = '专辑'
        '${imported ? ' · 本地' : ''}'
        '${downloaded ? ' · 已下载' : ''}';
    final meta = <String>[
      artist,
      if (year != null) '$year',
      if (genre != null && genre.isNotEmpty) genre,
      '${songs.length} 首',
      '${(totalSec / 60).round()} 分钟',
    ].where((part) => part.isNotEmpty).join(' · ');

    /// 是否是当前这张专辑（可能按 id 命中，也可能按专辑名命中）
    bool isSelf(CatalogAlbum item) => item.id == albumId || item.title == title;

    // 同类型专辑优先，其余补齐（等价原型 renderAlbum 的排序）
    final sameGenre = genre == null || genre.isEmpty
        ? const <CatalogAlbum>[]
        : source.catalog.albums
            .where((item) => item.genre == genre && !isSelf(item))
            .toList(growable: false);
    final others = genre == null || genre.isEmpty
        ? source.catalog.albums
            .where((item) => !isSelf(item))
            .toList(growable: false)
        : source.catalog.albums
            .where((item) => item.genre != genre && !isSelf(item))
            .toList(growable: false);
    final related = [...sameGenre, ...others].take(6).toList(growable: false);
    // 卡片只认 core 的 Album，这里一次性派生，避免同一张专辑被反复组装
    final relatedCards = [
      for (final item in related) _coreAlbumOf(source, item),
    ];

    return PageShell(
      topPadding: UiV2Spacing.s4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiV2Hero(
            art: UiV2Cover(source: cover, size: double.infinity, radius: 0),
            type: type,
            title: title,
            meta: meta,
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
              UiV2Button(
                label: downloaded ? '已下载' : '下载',
                icon: downloaded ? UiV2Icons.check : UiV2Icons.download,
                variant: UiV2ButtonVariant.outline,
                onTap: () => _downloadAll(context, ref, songs, title),
              ),
              // 艺人入口：原型里点歌手名进 renderArtist；此前专辑页没有任何跳转，
              // 导致 artist 路由虽然注册了却无法到达。
              if (artist.isNotEmpty)
                UiV2Button(
                  label: '歌手 · $artist',
                  icon: UiV2Icons.user,
                  variant: UiV2ButtonVariant.outline,
                  onTap: () =>
                      ref.read(navProvider.notifier).go('artist', artist),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: UiV2Spacing.s3),
            child: Text(
              '曲目',
              style: UiV2Text.sectionTitle.copyWith(color: t.text),
            ),
          ),
          UiV2Panel(
            child: UiV2TrackList(
              rows: [
                for (var i = 0; i < songs.length; i++)
                  UiV2SongRow(
                    song: songs[i],
                    meta: metas[songs[i].id],
                    index: i,
                    showAlbum: false,
                    onTap: () => TrackActions.playAt(context, ref, songs, i),
                    onToggleLike: () =>
                        TrackActions.toggleLike(context, ref, songs[i]),
                    onMore: () =>
                        showTrackMenu(context, song: songs[i]),
                  ),
              ],
            ),
          ),
          if (relatedCards.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: UiV2Spacing.s6),
              child: UiV2Section(
                title: '同类型专辑',
                child: UiV2Rail(
                  children: [
                    for (final item in relatedCards)
                      UiV2AlbumCard(
                        album: item,
                        onTap: () => ref
                            .read(navProvider.notifier)
                            .go('album', item.id),
                        onPlay: () =>
                            TrackActions.playAll(context, ref, item.songs),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 逐首下载专辑曲目，并如实汇报结果
  ///
  /// [DownloadActions.download] 在源没有播放地址时返回 null（任务记为 failed），
  /// 所以这里用 [DownloadManager.getTasks] 区分「已排入队列」与「没有地址」，
  /// 不把失败说成成功。
  static Future<void> _downloadAll(
    BuildContext context,
    WidgetRef ref,
    List<Song> songs,
    String albumTitle,
  ) async {
    final actions = ref.read(downloadActionsProvider);
    final manager = ref.read(downloadManagerProvider);
    var started = 0;
    var cached = 0;
    var failed = 0;

    for (final song in songs) {
      if ((song.localPath ?? '').isNotEmpty) {
        cached++;
        continue;
      }
      try {
        final path = await actions.download(song);
        if (path != null) {
          cached++;
          continue;
        }
        final task = manager
            .getTasks()
            .where((item) => item.songKey == song.globalKey)
            .lastOrNull;
        if (task?.status == DownloadStatus.failed) {
          failed++;
        } else {
          started++;
        }
      } catch (_) {
        // 单首失败不影响其余曲目
        failed++;
      }
    }

    if (!context.mounted) return;
    if (started > 0) {
      showUiV2Toast(
        context,
        failed > 0
            ? '已开始下载 $started 首，$failed 首没有可用地址'
            : '开始下载「$albumTitle」的 $started 首',
      );
      return;
    }
    if (failed > 0) {
      showUiV2Toast(
        context,
        '「$albumTitle」里 $failed 首都没有可用的下载地址',
        info: true,
      );
      return;
    }
    showUiV2Toast(context, '「$albumTitle」已在本地（$cached 首）');
  }
}

/// 把演示曲库的专辑派生成 core 的 [Album]
///
/// 卡片组件（[UiV2AlbumCard]）与播放入口只认 core 模型，这里用源自身的曲目
/// 映射（[CatalogMusicSource.songOf]）组装，不做类型强转。
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
