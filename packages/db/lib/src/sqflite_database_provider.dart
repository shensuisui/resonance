/// SQLite 数据库提供者
///
/// 实现 core 的 DatabaseProvider 接口，
/// 组装四个 SQLite DAO 实例，提供跨平台持久化。

import 'package:core/core.dart';
import 'database_helper.dart';
import 'sqflite_song_dao.dart';
import 'sqflite_playlist_dao.dart';
import 'sqflite_recent_plays_dao.dart';
import 'sqflite_favorites_dao.dart';
import 'sqflite_settings_dao.dart';
import 'sqflite_play_progress_dao.dart';

class SqfliteDatabaseProvider implements DatabaseProvider {
  final DatabaseHelper _helper;

  late final SongDao _songDao;
  late final PlaylistDao _playlistDao;
  late final RecentPlaysDao _recentPlaysDao;
  late final FavoritesDao _favoritesDao;
  late final SettingsDao _settingsDao;
  late final PlayProgressDao _playProgressDao;

  SqfliteDatabaseProvider() : _helper = DatabaseHelper();

  SqfliteDatabaseProvider.withHelper(this._helper);

  @override
  Future<void> initialize() async {
    await _helper.getDatabase();
    _songDao = SqfliteSongDao(_helper);
    _playlistDao = SqflitePlaylistDao(_helper);
    _recentPlaysDao = SqfliteRecentPlaysDao(_helper);
    _favoritesDao = SqfliteFavoritesDao(_helper);
    _settingsDao = SqfliteSettingsDao(_helper);
    _playProgressDao = SqflitePlayProgressDao(_helper);
  }

  @override
  SongDao get songDao => _songDao;
  @override
  PlaylistDao get playlistDao => _playlistDao;
  @override
  RecentPlaysDao get recentPlaysDao => _recentPlaysDao;
  @override
  FavoritesDao get favoritesDao => _favoritesDao;
  @override
  SettingsDao get settingsDao => _settingsDao;
  @override
  PlayProgressDao get playProgressDao => _playProgressDao;

  Future<void> close() async {
    await _helper.close();
  }
}
