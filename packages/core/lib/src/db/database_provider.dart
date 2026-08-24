import 'package:core/core.dart';

/// 数据库提供者抽象
/// 由上层（ui 或 fm_app）注入具体实现（如 sqflite）
abstract class DatabaseProvider {
  Future<void> initialize();
  SongDao get songDao;
  PlaylistDao get playlistDao;
  RecentPlaysDao get recentPlaysDao;
  FavoritesDao get favoritesDao;
}

/// 歌曲 DAO 接口
abstract class SongDao {
  Future<void> insertSong(Song song);
  Future<Song?> getSong(String id, String sourceId);
  Future<List<Song>> searchSongs(String keyword);
  Future<void> updateSong(Song song);
  Future<void> deleteSong(String id, String sourceId);
}

/// 歌单 DAO 接口
abstract class PlaylistDao {
  Future<void> insertPlaylist(Playlist playlist);
  Future<Playlist?> getPlaylist(String id);
  Future<List<Playlist>> getAllPlaylists();
  Future<void> updatePlaylist(Playlist playlist);
  Future<void> deletePlaylist(String id);
}

/// 最近播放 DAO 接口
abstract class RecentPlaysDao {
  Future<void> insertOrUpdateRecentPlay(String songKey, int playedAt);
  Future<List<String>> getRecentPlayKeys({int limit = 500});
  Future<void> cleanOldest(int maxCount);
}

/// 收藏 DAO 接口
abstract class FavoritesDao {
  Future<void> addFavorite(String songKey, int time);
  Future<void> removeFavorite(String songKey);
  Future<bool> isFavorite(String songKey);
  Future<List<String>> getAllFavoriteKeys();
}