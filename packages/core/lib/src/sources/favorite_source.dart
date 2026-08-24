import 'package:core/core.dart';

/// 最喜欢源
/// 跨源收藏系统，只存储歌曲标识，不复制文件
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
  );

  /// 添加喜欢
  Future<void> addFavorite(String songKey, String sourceId, String songId) async {
    await _favoritesDao.addFavorite(songKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// 取消喜欢
  Future<void> removeFavorite(String songKey) async {
    await _favoritesDao.removeFavorite(songKey);
  }

  /// 是否已喜欢
  Future<bool> isFavorite(String songKey) async {
    return _favoritesDao.isFavorite(songKey);
  }

  /// 获取最喜欢的歌曲列表（回源获取详情）
  Future<List<Song>> getFavoriteSongs() async {
    final keys = await _favoritesDao.getAllFavoriteKeys();
    final songs = <Song>[];
    for (final key in keys) {
      final parts = key.split(':');
      if (parts.length < 2) continue;
      final sourceId = parts[0];
      final songId = parts.sublist(1).join(':');
      try {
        final song = await _sourceManager.getSongDetail(sourceId, songId);
        songs.add(song);
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