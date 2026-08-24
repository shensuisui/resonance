import 'package:core/core.dart';

/// 本地扫描源
/// 扫描设备指定目录下的音频文件，提取元数据，构建本地曲库
class LocalScanSource extends MusicSource {
  @override
  final SourceInfo sourceInfo = const SourceInfo(
    id: 'local_scan',
    name: '本地音乐',
    type: SourceType.local,
    enabled: true,
  );

  final List<Song> _scannedSongs = [];
  bool _initialized = false;

  @override
  Future<void> init() async {
    _initialized = true;
  }

  @override
  Future<void> dispose() async {
    _scannedSongs.clear();
    _initialized = false;
  }

  /// 添加扫描到的歌曲
  void addScannedSongs(List<Song> songs) {
    for (final song in songs) {
      final index = _scannedSongs.indexWhere(
        (s) => s.id == song.id && s.sourceId == song.sourceId,
      );
      if (index >= 0) {
        _scannedSongs[index] = song;
      } else {
        _scannedSongs.add(song);
      }
    }
  }

  /// 获取已扫描的歌曲列表
  List<Song> getScannedSongs() => List.unmodifiable(_scannedSongs);

  /// 清除所有扫描结果
  void clear() => _scannedSongs.clear();

  @override
  Future<SearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 20,
  }) async {
    if (!_initialized) return SearchResult(songs: [], sourceId: 'local_scan');

    final lower = keyword.toLowerCase();
    final matched = _scannedSongs.where((s) =>
        s.title.toLowerCase().contains(lower) ||
        s.artist.toLowerCase().contains(lower)).toList();

    // 本地源不分页，全量返回
    return SearchResult(
      songs: matched,
      sourceId: 'local_scan',
      hasMore: false,
    );
  }

  @override
  Future<Song> getSongDetail(String id) async {
    final song = _scannedSongs.where((s) => s.id == id).firstOrNull;
    if (song == null) throw Exception('Song not found: $id');
    return song;
  }

  @override
  Future<String> getSongUrl(String id) async {
    final song = _scannedSongs.where((s) => s.id == id).firstOrNull;
    if (song == null) throw Exception('Song not found: $id');
    return song.playUrl ?? song.localPath ?? '';
  }

  @override
  Future<Lyrics?> getLyrics(String id) async {
    // 本地歌词暂不支持
    return null;
  }

  @override
  Future<Album?> getAlbum(String id) async {
    return null;
  }

  @override
  Future<Artist?> getArtist(String id) async {
    return null;
  }

  @override
  Future<Playlist?> getPlaylist(String id) async {
    return null;
  }
}