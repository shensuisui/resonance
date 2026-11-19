/// SQLite 数据库提供者
///
/// 实现 core 的 DatabaseProvider 接口，
/// 组装四个 SQLite DAO 实例，提供跨平台持久化。
///
/// 同时实现 [DbChangeSource]：任一 DAO 写库成功后通过总线广播变更，
/// 供同步层做「防抖推送」（见 packages/core/lib/src/db/db_change.dart）。

import 'package:core/core.dart';
import 'database_helper.dart';
import 'sqflite_song_dao.dart';
import 'sqflite_playlist_dao.dart';
import 'sqflite_recent_plays_dao.dart';
import 'sqflite_favorites_dao.dart';
import 'sqflite_settings_dao.dart';
import 'sqflite_play_progress_dao.dart';
import 'download_task_dao.dart';

class SqfliteDatabaseProvider implements DatabaseProvider, DbChangeSource {
  final DatabaseHelper _helper;

  /// 写变更总线：DAO 写后广播，同步层订阅做防抖推送
  final DbChangeBus _changeBus = DbChangeBus();

  late final SongDao _songDao;
  late final PlaylistDao _playlistDao;
  late final RecentPlaysDao _recentPlaysDao;
  late final FavoritesDao _favoritesDao;
  late final SettingsDao _settingsDao;
  late final PlayProgressDao _playProgressDao;
  late final DownloadTaskDao _downloadTaskDao;

  SqfliteDatabaseProvider() : _helper = DatabaseHelper();

  SqfliteDatabaseProvider.withHelper(this._helper);

  @override
  Future<void> initialize() async {
    await _helper.getDatabase();
    _songDao = SqfliteSongDao(_helper, changeBus: _changeBus);
    _playlistDao = SqflitePlaylistDao(_helper, changeBus: _changeBus);
    _recentPlaysDao = SqfliteRecentPlaysDao(_helper, changeBus: _changeBus);
    _favoritesDao = SqfliteFavoritesDao(_helper, changeBus: _changeBus);
    _settingsDao = SqfliteSettingsDao(_helper, changeBus: _changeBus);
    _playProgressDao = SqflitePlayProgressDao(_helper, changeBus: _changeBus);
    _downloadTaskDao = SqfliteDownloadTaskDao(_helper);
  }

  @override
  Stream<DbChange> get changes => _changeBus.changes;

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
  @override
  DownloadTaskDao get downloadTaskDao => _downloadTaskDao;

  Future<void> close() async {
    await _changeBus.dispose();
    await _helper.close();
  }
}
