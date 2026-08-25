/// SongDao 的 SQLite 实现
///
/// 使用 sqflite 对 songs 表执行 CRUD，
/// 复合主键 (id, source_id) 对应 Song 的全局唯一约束。

import 'package:core/core.dart';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class SqfliteSongDao implements SongDao {
  final DatabaseHelper _helper;

  SqfliteSongDao(this._helper);

  Future<Database> get _db => _helper.getDatabase();

  @override
  Future<void> insertSong(Song song) async {
    final db = await _db;
    await db.insert(
      'songs',
      songToMap(song),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<Song?> getSong(String id, String sourceId) async {
    final db = await _db;
    final rows = await db.query(
      'songs',
      where: 'id = ? AND source_id = ?',
      whereArgs: [id, sourceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return songFromMap(rows.first);
  }

  @override
  Future<List<Song>> searchSongs(String keyword) async {
    final db = await _db;
    final lower = '%${keyword.toLowerCase()}%';
    final rows = await db.query(
      'songs',
      where: 'LOWER(title) LIKE ? OR LOWER(artist) LIKE ?',
      whereArgs: [lower, lower],
    );
    return rows.map(songFromMap).toList();
  }

  @override
  Future<void> updateSong(Song song) async {
    final db = await _db;
    await db.update(
      'songs',
      songToMap(song),
      where: 'id = ? AND source_id = ?',
      whereArgs: [song.id, song.sourceId],
    );
  }

  @override
  Future<void> deleteSong(String id, String sourceId) async {
    final db = await _db;
    await db.delete(
      'songs',
      where: 'id = ? AND source_id = ?',
      whereArgs: [id, sourceId],
    );
  }
}
