import 'package:core/core.dart';

/// 最喜欢源
/// 跨源收藏系统，只存储歌曲标识 + 元数据快照，不复制文件
class FavoriteSource extends MusicSource {
  final FavoritesDao _favoritesDao;
  final SourceManager _sourceManager;

  FavoriteSource(this._favoritesDao, this._sourceManager);

  @override
  final SourceInfo sourceInfo = const SourceInfo(
    id: 'favorite',
    name: '我最喜欢',
    type: SourceType.local,
    enabled: true,
    // 收藏是聚合视图，不占音乐库分栏
    showInLibrary: false,
  );

  /// 添加喜欢（保存歌曲快照，供列表直接渲染）
  Future<void> addFavorite(Song song) async {
    await _favoritesDao.addFavorite(
      song.globalKey,
      DateTime.now().millisecondsSinceEpoch,
      title: song.title,
      artist: song.artist,
      coverUrl: song.coverUrl,
    );
  }

  /// 取消喜欢
  Future<void> removeFavorite(String songKey) async {
    await _favoritesDao.removeFavorite(songKey);
  }

  /// 是否已喜欢
  Future<bool> isFavorite(String songKey) async {
    return _favoritesDao.isFavorite(songKey);
  }

  /// 获取最喜欢的歌曲列表
  ///
  /// 优先使用快照直接渲染；历史收藏（快照功能前写入，title 为 null）
  /// 回退回源补齐详情。
  Future<List<Song>> getFavoriteSongs() async {
    final records = await _favoritesDao.getAllFavoriteRecords();
    final songs = <Song>[];
    for (final record in records) {
      final parts = record.songKey.split(':');
      if (parts.length < 2) continue;
      final sourceId = parts[0];
      final songId = parts.sublist(1).join(':');

      if (record.title != null) {
        songs.add(Song(
          id: songId,
          sourceId: sourceId,
          title: record.title!,
          artist: record.artist ?? '',
          coverUrl: record.coverUrl,
        ));
        continue;
      }

      // 旧记录回退：回源补齐
      try {
        songs.add(await _sourceManager.getSongDetail(sourceId, songId));
      } catch (_) {
        // 源不可用时跳过
      }
    }
    return songs;
  }

  @override
  Future<SearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 20,
  }) async {
    final keys = await _favoritesDao.getAllFavoriteKeys();
    final matched = <Song>[];
    final lower = keyword.toLowerCase();

    for (final key in keys) {
      final parts = key.split(':');
      if (parts.length < 2) continue;
      final sourceId = parts[0];
      final songId = parts.sublist(1).join(':');
      try {
        final song = await _sourceManager.getSongDetail(sourceId, songId);
        if (song.title.toLowerCase().contains(lower) ||
            song.artist.toLowerCase().contains(lower)) {
          matched.add(song);
        }
      } catch (_) {}
    }

    return SearchResult(
      songs: matched,
      sourceId: 'favorite',
      hasMore: false,
    );
  }

  @override
  Future<Song> getSongDetail(String id) async {
    // id 格式: sourceId:songId
    final parts = id.split(':');
    if (parts.length < 2) throw Exception('Invalid favorite song key: $id');
    return _sourceManager.getSongDetail(parts[0], parts.sublist(1).join(':'));
  }

  @override
  Future<String> getSongUrl(String id) async {
    final parts = id.split(':');
    if (parts.length < 2) throw Exception('Invalid favorite song key: $id');
    return _sourceManager.getSongUrl(parts[0], parts.sublist(1).join(':'));
  }

  @override
  Future<Lyrics?> getLyrics(String id) async {
    final parts = id.split(':');
    if (parts.length < 2) return null;
    return _sourceManager.getLyrics(parts[0], parts.sublist(1).join(':'));
  }

  @override
  Future<Album?> getAlbum(String id) async => null;

  @override
  Future<Artist?> getArtist(String id) async => null;

  @override
  Future<Playlist?> getPlaylist(String id) async => null;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}
}