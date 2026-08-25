/// PlaylistDao 的 SQLite 实现
///
/// 歌单数据分布在 playlists 表和 playlist_songs 关联表。
/// songKeys 列表通过关联表按 position 排序重建。

import 'package:core/core.dart';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class SqflitePlaylistDao implements PlaylistDao {
  final DatabaseHelper _helper;

  SqflitePlaylistDao(this._helper);

  Future<Database> get _db => _helper.getDatabase();

  @override
  Future<void> insertPlaylist(Playlist playlist) async {
    final db = await _db;
    await db.transaction((txn) async {
      // 插入歌单行
      await txn.insert('playlists', {
        'id': playlist.id,
        'name': playlist.name,
        'source_id': playlist.sourceId,
        'source_playlist_id': playlist.sourcePlaylistId,
        'cover_url': playlist.coverUrl,
        'created_time': playlist.createdTime.millisecondsSinceEpoch,
        'modified_time': playlist.modifiedTime.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // 批量插入歌单-歌曲关联
      for (int i = 0; i < playlist.songKeys.length; i++) {
        await txn.insert('playlist_songs', {
          'playlist_id': playlist.id,
          'song_key': playlist.songKeys[i],
          'position': i,
        });
      }
    });
  }

  @override
  Future<Playlist?> getPlaylist(String id) async {
    final db = await _db;
    final rows = await db.query('playlists',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;

    final row = rows.first;
    // 查关联表按 position 排序获取 songKeys
    final songRows = await db.query('playlist_songs',
        where: 'playlist_id = ?',
        whereArgs: [id],
        orderBy: 'position ASC');
    final songKeys = songRows.map((r) => r['song_key'] as String).toList();

    return _mapToPlaylist(row, songKeys);
  }

  @override
  Future<List<Playlist>> getAllPlaylists() async {
    final db = await _db;
    final rows = await db.query('playlists', orderBy: 'modified_time DESC');

    final playlists = <Playlist>[];
    for (final row in rows) {
      final songRows = await db.query('playlist_songs',
          where: 'playlist_id = ?',
          whereArgs: [row['id']],
          orderBy: 'position ASC');
      final songKeys = songRows.map((r) => r['song_key'] as String).toList();
      playlists.add(_mapToPlaylist(row, songKeys));
    }
    return playlists;
  }

  @override
  Future<void> updatePlaylist(Playlist playlist) async {
    final db = await _db;
    await db.transaction((txn) async {
      // 更新歌单行
      await txn.update('playlists', {
        'name': playlist.name,
        'source_id': playlist.sourceId,
        'source_playlist_id': playlist.sourcePlaylistId,
        'cover_url': playlist.coverUrl,
        'modified_time': playlist.modifiedTime.millisecondsSinceEpoch,
      }, where: 'id = ?', whereArgs: [playlist.id]);

      // 删旧关联数据，重新插入
      await txn.delete('playlist_songs',
          where: 'playlist_id = ?', whereArgs: [playlist.id]);
      for (int i = 0; i < playlist.songKeys.length; i++) {
        await txn.insert('playlist_songs', {
          'playlist_id': playlist.id,
          'song_key': playlist.songKeys[i],
          'position': i,
        });
      }
    });
  }

  @override
  Future<void> deletePlaylist(String id) async {
    final db = await _db;
    await db.transaction((txn) async {
      // 先删关联（sqflite 默认不启用 CASCADE，手动删）
      await txn.delete('playlist_songs',
          where: 'playlist_id = ?', whereArgs: [id]);
      await txn.delete('playlists', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// DB 行 → Playlist
  Playlist _mapToPlaylist(Map<String, Object?> row, List<String> songKeys) {
    return Playlist(
      id: row['id'] as String,
      name: row['name'] as String,
      songKeys: songKeys,
      sourceId: row['source_id'] as String?,
      sourcePlaylistId: row['source_playlist_id'] as String?,
      coverUrl: row['cover_url'] as String?,
      createdTime: DateTime.fromMillisecondsSinceEpoch(
          row['created_time'] as int),
      modifiedTime: DateTime.fromMillisecondsSinceEpoch(
          row['modified_time'] as int),
    );
  }
}
