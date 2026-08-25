/// FavoritesDao 的 SQLite 实现

import 'package:core/core.dart';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class SqfliteFavoritesDao implements FavoritesDao {
  final DatabaseHelper _helper;

  SqfliteFavoritesDao(this._helper);

  Future<Database> get _db => _helper.getDatabase();

  @override
  Future<void> addFavorite(String songKey, int time) async {
    final db = await _db;
    await db.insert('favorites', {
      'song_key': songKey,
      'favorite_time': time,
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
}
