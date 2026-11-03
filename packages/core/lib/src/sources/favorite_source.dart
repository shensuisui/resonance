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
    visible: false,
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

  /// 搜索收藏
  ///
  /// 用**收藏快照**（title/artist/coverUrl）在本地匹配 —— 收藏时就存了这些字段，
  /// 不需要回源。旧实现是拿 keys 逐条 `getSongDetail` **串行**去问远端：
  /// 收藏越多越慢（用户实测「我最喜欢」这个本地源比所有远端源都慢、排在最后），
  /// 而且拿不到快照里的封面。
  ///
  /// 只有快照功能之前写入的历史记录（title 为 null）才回源补齐，且这批并行取，
  /// 不串行等待。
  @override
  Future<SearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 20,
  }) async {
    final records = await _favoritesDao.getAllFavoriteRecords();
    final lower = keyword.toLowerCase();
    final matched = <Song>[];
    final legacy = <(String, String)>[];

    for (final record in records) {
      final parts = record.songKey.split(':');
      if (parts.length < 2) continue;
      final sourceId = parts[0];
      final songId = parts.sublist(1).join(':');

      final title = record.title;
      if (title == null) {
        legacy.add((sourceId, songId));
        continue;
      }
      if (title.toLowerCase().contains(lower) ||
          (record.artist ?? '').toLowerCase().contains(lower)) {
        matched.add(Song(
          id: songId,
          sourceId: sourceId,
          title: title,
          artist: record.artist ?? '',
          coverUrl: record.coverUrl,
        ));
      }
    }

    if (legacy.isNotEmpty) {
      final details = await Future.wait(
        legacy.map((e) async {
          try {
            return await _sourceManager.getSongDetail(e.$1, e.$2);
          } catch (_) {
            return null;
          }
        }),
      );
      for (final song in details) {
        if (song == null) continue;
        if (song.title.toLowerCase().contains(lower) ||
            song.artist.toLowerCase().contains(lower)) {
          matched.add(song);
        }
      }
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