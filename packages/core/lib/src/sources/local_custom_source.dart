import 'package:core/core.dart';

/// 本地自建源
/// 用户手动添加单首歌曲，持久化在本地数据库中
class LocalCustomSource extends MusicSource {
  final SongDao _songDao;

  LocalCustomSource(this._songDao);

  @override
  final SourceInfo sourceInfo = const SourceInfo(
    id: 'local_custom',
    name: '自建歌曲',
    type: SourceType.local,
    enabled: true,
    // 自建歌曲需要在音乐库里直接管理
    showInLibrary: true,
    visible: false,
  );

  /// 添加自定义歌曲
  Future<void> addCustomSong(Song song) async {
    final customSong = song.copyWith(sourceId: 'local_custom');
    await _songDao.insertSong(customSong);
  }

  /// 删除自定义歌曲
  Future<void> removeCustomSong(String id) async {
    await _songDao.deleteSong(id, 'local_custom');
  }

  /// 获取所有自定义歌曲
  Future<List<Song>> getAllCustomSongs() async {
    // 通过搜索空字符串获取全部
    return _songDao.searchSongs('');
  }

  /// 编辑歌曲元信息
  Future<void> updateCustomSong(Song song) async {
    await _songDao.updateSong(song);
  }

  @override
  Future<SearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 20,
  }) async {
    final songs = await _songDao.searchSongs(keyword);
    final filtered = songs.where((s) => s.sourceId == 'local_custom').toList();
    return SearchResult(
      songs: filtered,
      sourceId: 'local_custom',
      hasMore: false,
    );
  }

  @override
  Future<Song> getSongDetail(String id) async {
    final song = await _songDao.getSong(id, 'local_custom');
    if (song == null) throw Exception('Custom song not found: $id');
    return song;
  }

  @override
  Future<String> getSongUrl(String id) async {
    final song = await _songDao.getSong(id, 'local_custom');
    if (song == null) throw Exception('Custom song not found: $id');
    return song.playUrl ?? song.localPath ?? '';
  }

  @override
  Future<Lyrics?> getLyrics(String id) async => null;

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