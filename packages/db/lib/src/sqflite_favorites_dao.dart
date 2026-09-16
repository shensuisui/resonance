/// FavoritesDao 的 SQLite 实现
///
/// 保存歌曲快照（title/artist/cover_url），
/// 「我最喜欢」列表直接读快照渲染，无需回源查询。

import 'package:core/core.dart';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class SqfliteFavoritesDao implements FavoritesDao {
  final DatabaseHelper _helper;

  SqfliteFavoritesDao(this._helper);

  Future<Database> get _db => _helper.getDatabase();

  @override
  Future<void> addFavorite(
    String songKey,
    int time, {
    String? title,
    String? artist,
    String? coverUrl,
  }) async {
    final db = await _db;
    await db.insert('favorites', {
      'song_key': songKey,
      'favorite_time': time,
      'title': title,
      'artist': artist,
      'cover_url': coverUrl,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> removeFavorite(String songKey) async {
    final db = await _db;
    await db.delete('favorites',
        where: 'song_key = ?', whereArgs: [songKey]);
  }

  @override
  Future<bool> isFavorite(String songKey) async {
    final db = await _db;
    final rows = await db.query('favorites',
        where: 'song_key = ?', whereArgs: [songKey], limit: 1);
    return rows.isNotEmpty;
  }

  @override
  Future<List<String>> getAllFavoriteKeys() async {
    final db = await _db;
    final rows = await db.query('favorites', orderBy: 'favorite_time DESC');
    return rows.map((r) => r['song_key'] as String).toList();
  }

  @override
  Future<List<FavoriteRecord>> getAllFavoriteRecords() async {
    final db = await _db;
    final rows = await db.query('favorites', orderBy: 'favorite_time DESC');
    return rows
        .map((r) => FavoriteRecord(
              songKey: r['song_key'] as String,
              time: r['favorite_time'] as int,
              title: r['title'] as String?,
              artist: r['artist'] as String?,
              coverUrl: r['cover_url'] as String?,
            ))
        .toList();
  }
}