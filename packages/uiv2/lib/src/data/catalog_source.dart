/// 演示曲库音乐源 —— 把原型的内置配表接成项目里**真实的一个音乐源**。
///
/// 背景：原型（assets/app.js）把 16 张专辑、曲目、歌单直接写在前端内存里，
/// 页面全部从 `TRACK_BY_ID` 这类内存表取数。uiv2 不能这么做——项目已经有一套
/// 完整的真实能力（core 的 [MusicSource] / [SourceManager] / DAO / 播放器），
/// 所以这里把配表**包装成实现 [MusicSource] 的源**，由壳工程注册进 SourceManager：
///
///   * 搜索、歌单、专辑、艺人、歌词全部走 SourceManager 的既有入口；
///   * 页面从 DAO / provider 取数，代码里不再有「mock 分支」；
///   * 该源与本地扫描源、规则源、插件源**完全同构**，可以在「音乐源」页里
///     像其它源一样启用/停用，停用后它就不再出现在聚合搜索与推荐里。
///
/// 诚实说明（不做假）：本源的曲目只有元数据、没有音频文件，
/// [getSongUrl] 返回空字符串——播放链路会如实报告「源未提供播放地址」。
library;

import 'package:core/core.dart';

import 'catalog.dart';
import 'lyrics.dart' as demo;

/// 演示曲库源的 id（与本地源一样是固定 id，注册一次即可）
const String kCatalogSourceId = 'demo_catalog';

/// 演示曲库音乐源
class CatalogMusicSource implements MusicSource {
  /// 曲库（由配表派生，构造时构建一次）
  final Catalog catalog;

  /// 所有曲目共用的播放地址（可播占位音频的 file:// URI）
  ///
  /// 演示配表本身没有音频，[getSongUrl] 曾恒返回空串，于是"点歌不播、播放页/歌词/
  /// 队列全都进不去"。壳工程启动时生成一段静音 wav 并通过这里注入，
  /// 让演示曲库也能走通完整播放链路；不注入时仍返回空串（行为与以前一致）。
  final String audioUri;

  /// 构造源；不传 [catalog] 时用 [Catalog.build] 构建默认曲库
  CatalogMusicSource({Catalog? catalog, this.audioUri = ''})
      : catalog = catalog ?? Catalog.build();

  @override
  SourceInfo get sourceInfo => const SourceInfo(
        id: kCatalogSourceId,
        name: '演示曲库',
        type: SourceType.local,
        enabled: true,
      );

  // ==================== 曲目 ====================

  /// 把配表曲目转成 core 的 [Song]（这是本源的唯一映射点）
  Song songOf(CatalogTrack track) => Song(
        id: track.id,
        sourceId: kCatalogSourceId,
        title: track.title,
        artist: track.artist,
        album: track.album,
        coverUrl: track.cover,
        duration: track.duration,
        // 配表里的额外信息通过 extra 透传，便于 UI 展示「本地/已下载/流派」
        extra: {
          'genre': track.genre,
          'albumId': track.albumId,
          'no': track.no,
          'local': track.local,
          'downloaded': track.downloaded,
        },
      );

  /// 全部曲目
  List<Song> get allSongs =>
      catalog.tracks.map(songOf).toList(growable: false);

  /// 按 id 取曲目（id 形如 `midnights#3`）
  CatalogTrack? trackById(String id) => catalog.track(id);

  @override
  Future<SearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 20,
  }) async {
    final q = keyword.trim().toLowerCase();
    if (q.isEmpty) {
      return const SearchResult(songs: [], sourceId: kCatalogSourceId);
    }
    final hits = catalog.tracks
        .where((t) =>
            '${t.title} ${t.artist} ${t.album}'.toLowerCase().contains(q) ||
            t.genre.toLowerCase().contains(q))
        .toList();
    final start = ((page - 1) * pageSize).clamp(0, hits.length);
    final end = (start + pageSize).clamp(0, hits.length);
    return SearchResult(
      songs: hits.sublist(start, end).map(songOf).toList(),
      hasMore: end < hits.length,
      nextPage: end < hits.length ? page + 1 : null,
      sourceId: kCatalogSourceId,
    );
  }

  @override
  Future<Song> getSongDetail(String id) async {
    final track = catalog.track(id);
    if (track == null) {
      throw StateError('演示曲库里没有曲目 $id');
    }
    return songOf(track);
  }

  /// 演示曲库没有音频文件：如实返回空串，由播放链路报「源未提供播放地址」。
  @override
  Future<String> getSongUrl(String id) async => audioUri;

  // ==================== 歌词 ====================

  /// 内置原创演示歌词（按曲目时长均分时间轴，与原型算法一致）。
  @override
  Future<Lyrics?> getLyrics(String id) async {
    final track = catalog.track(id);
    if (track == null) return null;
    final script = demo.buildLyricScript(
      trackId: id,
      durationSeconds: track.duration,
    );
    if (!script.hasLyrics) return null;
    return Lyrics(
      songId: id,
      sourceId: kCatalogSourceId,
      isLrc: false,
      lines: [
        for (final entry in script.entries)
          LyricLine(text: entry.text, time: entry.at ?? Duration.zero),
      ],
    );
  }

  // ==================== 专辑 / 艺人 / 歌单 ====================

  @override
  Future<Album?> getAlbum(String id) async {
    final album = catalog.album(id);
    if (album == null) return null;
    return Album(
      id: album.id,
      sourceId: kCatalogSourceId,
      title: album.title,
      artist: album.artist,
      coverUrl: album.cover,
      songCount: album.tracks.length,
      songs: album.tracks.map(songOf).toList(),
      extra: {
        'year': album.year,
        'genre': album.genre,
        'imported': album.imported,
        'downloaded': album.downloaded,
      },
    );
  }

  @override
  Future<Artist?> getArtist(String id) async {
    final artist = catalog.artists.where((a) => a.name == id).firstOrNull;
    if (artist == null) return null;
    return Artist(
      id: artist.name,
      sourceId: kCatalogSourceId,
      name: artist.name,
      avatar: artist.albums.first.cover,
      description: '${artist.albums.length} 张专辑 · ${artist.tracks.length} 首歌',
      extra: {'albums': artist.albums.map((a) => a.id).toList()},
    );
  }

  /// 歌单（配表里的 6 个编辑精选 + 1 个自建示例）
  @override
  Future<Playlist?> getPlaylist(String id) async {
    final seed = kPlaylistSeeds.where((p) => p.id == id).firstOrNull;
    if (seed == null) return null;
    final songs = catalog.resolve(seed.refs);
    return Playlist(
      id: seed.id,
      name: seed.name,
      sourceId: kCatalogSourceId,
      coverUrl: songs.isEmpty ? null : songs.first.cover,
      songKeys: songs.map((t) => '$kCatalogSourceId:${t.id}').toList(),
      songSnapshots: {for (final s in songs) '$kCatalogSourceId:${s.id}': songOf(s)},
      createdTime: DateTime.fromMillisecondsSinceEpoch(0),
      modifiedTime: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  @override
  Future<List<Song>> getPlaylistSongs(String id) async {
    final seed = kPlaylistSeeds.where((p) => p.id == id).firstOrNull;
    if (seed == null) return const [];
    return catalog.resolve(seed.refs).map(songOf).toList();
  }

  @override
  Future<List<Playlist>> getPlaylistList({int page = 1}) async {
    if (page > 1) return const [];
    final out = <Playlist>[];
    for (final seed in kPlaylistSeeds) {
      final p = await getPlaylist(seed.id);
      if (p != null) out.add(p);
    }
    return out;
  }

  // ==================== 生命周期 ====================

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}
}
