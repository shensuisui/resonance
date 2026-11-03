import 'package:core/core.dart';

/// 数据库提供者抽象
/// 由上层（ui 或 resonance_app）注入具体实现（如 sqflite）
abstract class DatabaseProvider {
  Future<void> initialize();
  SongDao get songDao;
  PlaylistDao get playlistDao;
  RecentPlaysDao get recentPlaysDao;
  FavoritesDao get favoritesDao;
  SettingsDao get settingsDao;
  PlayProgressDao get playProgressDao;
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
  /// 插入/更新最近播放记录（songKey 去重移顶）
  ///
  /// [title]/[artist]/[coverUrl] 为歌曲快照：记录播放时的元数据，
  /// UI 直接渲染快照，无需回源 getSongDetail（规则源的详情接口
  /// 可能不返回标题/歌手，导致列表名字为空）。
  Future<void> insertOrUpdateRecentPlay(
    String songKey,
    int playedAt, {
    String? title,
    String? artist,
    String? coverUrl,
  });

  Future<List<String>> getRecentPlayKeys({int limit = 500});

  /// 获取最近播放记录（含歌曲快照，按播放时间倒序）
  Future<List<RecentPlayRecord>> getRecentPlayRecords({int limit = 500});

  Future<void> cleanOldest(int maxCount);

  /// 移除一条记录（最近播放列表里的「移除」用）
  Future<void> deleteRecentPlay(String songKey);
}

/// 收藏 DAO 接口
abstract class FavoritesDao {
  /// 添加收藏（songKey 去重），同时保存歌曲快照
  ///
  /// 快照（title/artist/coverUrl）供「我最喜欢」列表直接渲染，
  /// 避免回源 getSongDetail（规则源详情接口可能不返回标题导致名字为空）。
  Future<void> addFavorite(
    String songKey,
    int time, {
    String? title,
    String? artist,
    String? coverUrl,
  });

  Future<void> removeFavorite(String songKey);
  Future<bool> isFavorite(String songKey);
  Future<List<String>> getAllFavoriteKeys();

  /// 获取全部收藏记录（含歌曲快照）
  Future<List<FavoriteRecord>> getAllFavoriteRecords();
}

/// 收藏记录（含歌曲快照）
class FavoriteRecord {
  final String songKey;
  final int time;
  final String? title;
  final String? artist;
  final String? coverUrl;

  const FavoriteRecord({
    required this.songKey,
    required this.time,
    this.title,
    this.artist,
    this.coverUrl,
  });
}

/// 设置 DAO 接口（key-value 存储，支持多设备同步预留）
abstract class SettingsDao {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
  Future<Map<String, String>> getAll();
  Future<void> delete(String key);
}