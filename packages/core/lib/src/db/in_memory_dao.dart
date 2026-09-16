// 歌曲 DAO 内存实现（用于测试）
// 生产环境使用 sqflite 实现替换

import 'package:core/core.dart';

class InMemorySongDao implements SongDao {
  final _store = <String, Song>{};

  String _key(String id, String sourceId) => '$sourceId:$id';

  @override
  Future<void> insertSong(Song song) async {
    _store[_key(song.id, song.sourceId)] = song;
  }

  @override
  Future<Song?> getSong(String id, String sourceId) async {
    return _store[_key(id, sourceId)];
  }

  @override
  Future<List<Song>> searchSongs(String keyword) async {
    final lower = keyword.toLowerCase();
    return _store.values
        .where((s) =>
            s.title.toLowerCase().contains(lower) ||
            s.artist.toLowerCase().contains(lower))
        .toList();
  }

  @override
  Future<void> updateSong(Song song) async {
    _store[_key(song.id, song.sourceId)] = song;
  }

  @override
  Future<void> deleteSong(String id, String sourceId) async {
    _store.remove(_key(id, sourceId));
  }
}

class InMemoryPlaylistDao implements PlaylistDao {
  final _store = <String, Playlist>{};

  @override
  Future<void> insertPlaylist(Playlist playlist) async {
    _store[playlist.id] = playlist;
  }

  @override
  Future<Playlist?> getPlaylist(String id) async {
    return _store[id];
  }

  @override
  Future<List<Playlist>> getAllPlaylists() async {
    return _store.values.toList();
  }

  @override
  Future<void> updatePlaylist(Playlist playlist) async {
    _store[playlist.id] = playlist;
  }

  @override
  Future<void> deletePlaylist(String id) async {
    _store.remove(id);
  }
}

class InMemoryRecentPlaysDao implements RecentPlaysDao {
  final _store = <String, RecentPlayRecord>{};

  @override
  Future<void> insertOrUpdateRecentPlay(
    String songKey,
    int playedAt, {
    String? title,
    String? artist,
    String? coverUrl,
  }) async {
    _store[songKey] = RecentPlayRecord(
      songKey: songKey,
      playedAt: playedAt,
      title: title,
      artist: artist,
      coverUrl: coverUrl,
    );
  }

  @override
  Future<List<String>> getRecentPlayKeys({int limit = 500}) async {
    final sorted = _store.values.toList()
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    return sorted.take(limit).map((e) => e.songKey).toList();
  }

  @override
  Future<List<RecentPlayRecord>> getRecentPlayRecords(
      {int limit = 500}) async {
    final sorted = _store.values.toList()
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    return sorted.take(limit).toList();
  }

  @override
  Future<void> cleanOldest(int maxCount) async {
    if (_store.length <= maxCount) return;
    final sorted = _store.values.toList()
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    final toRemove = sorted.skip(maxCount);
    for (final entry in toRemove) {
      _store.remove(entry.songKey);
    }
  }
}

class InMemoryFavoritesDao implements FavoritesDao {
  final _store = <String, FavoriteRecord>{};

  @override
  Future<void> addFavorite(
    String songKey,
    int time, {
    String? title,
    String? artist,
    String? coverUrl,
  }) async {
    _store[songKey] = FavoriteRecord(
      songKey: songKey,
      time: time,
      title: title,
      artist: artist,
      coverUrl: coverUrl,
    );
  }

  @override
  Future<void> removeFavorite(String songKey) async {
    _store.remove(songKey);
  }

  @override
  Future<bool> isFavorite(String songKey) async {
    return _store.containsKey(songKey);
  }

  @override
  Future<List<String>> getAllFavoriteKeys() async {
    return _store.keys.toList();
  }

  @override
  Future<List<FavoriteRecord>> getAllFavoriteRecords() async {
    final list = _store.values.toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    return list;
  }
}

/// 设置 DAO 内存实现
class InMemorySettingsDao implements SettingsDao {
  final _store = <String, String>{};

  @override
  Future<String?> get(String key) async => _store[key];

  @override
  Future<void> set(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<Map<String, String>> getAll() async =>
      Map<String, String>.from(_store);

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }
}

/// 内存数据库提供者（用于测试）
class InMemoryDatabaseProvider implements DatabaseProvider {
  @override
  late final SongDao songDao = InMemorySongDao();
  @override
  late final PlaylistDao playlistDao = InMemoryPlaylistDao();
  @override
  late final RecentPlaysDao recentPlaysDao = InMemoryRecentPlaysDao();
  @override
  late final FavoritesDao favoritesDao = InMemoryFavoritesDao();
  @override
  late final SettingsDao settingsDao = InMemorySettingsDao();

  @override
  Future<void> initialize() async {
    // 内存实现无需初始化
  }
}