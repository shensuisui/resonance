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

      // 批量插入歌单-歌曲关联（携带歌曲快照，供列表直接展示元数据）
      for (int i = 0; i < playlist.songKeys.length; i++) {
        await txn.insert(
            'playlist_songs', _songRow(playlist.id, playlist, i));
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
    final (songKeys, snapshots) = await _querySongs(db, id);

    return _mapToPlaylist(row, songKeys, snapshots);
  }

  @override
  Future<List<Playlist>> getAllPlaylists() async {
    final db = await _db;
    final rows = await db.query('playlists', orderBy: 'modified_time DESC');

    final playlists = <Playlist>[];
    for (final row in rows) {
      final (songKeys, snapshots) = await _querySongs(db, row['id'] as String);
      playlists.add(_mapToPlaylist(row, songKeys, snapshots));
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

      // 删旧关联数据，重新插入（携带歌曲快照）
      await txn.delete('playlist_songs',
          where: 'playlist_id = ?', whereArgs: [playlist.id]);
      for (int i = 0; i < playlist.songKeys.length; i++) {
        await txn.insert(
            'playlist_songs', _songRow(playlist.id, playlist, i));
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

  /// DB 行 → Playlist（songKeys 与快照一并重建）
  Playlist _mapToPlaylist(
      Map<String, Object?> row, List<String> songKeys,
      Map<String, Song> snapshots) {
    return Playlist(
      id: row['id'] as String,
      name: row['name'] as String,
      songKeys: songKeys,
      songSnapshots: snapshots,
      sourceId: row['source_id'] as String?,
      sourcePlaylistId: row['source_playlist_id'] as String?,
      coverUrl: row['cover_url'] as String?,
      createdTime: DateTime.fromMillisecondsSinceEpoch(
          row['created_time'] as int),
      modifiedTime: DateTime.fromMillisecondsSinceEpoch(
          row['modified_time'] as int),
    );
  }

  /// 查询某歌单的歌曲关联：返回 (songKeys 保序, songKey→快照)
  Future<(List<String>, Map<String, Song>)> _querySongs(
      Database db, String playlistId) async {
    final songRows = await db.query('playlist_songs',
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
        orderBy: 'position ASC');
    final songKeys = <String>[];
    final snapshots = <String, Song>{};
    for (final r in songRows) {
      final key = r['song_key'] as String;
      songKeys.add(key);
      final snap = _snapshotFromRow(r);
      if (snap != null) snapshots[key] = snap;
    }
    return (songKeys, snapshots);
  }

  /// 关联表行 → 歌曲快照（无快照列/名称为空返回 null）
  Song? _snapshotFromRow(Map<String, Object?> row) {
    final title = row['title'] as String?;
    if (title == null || title.isEmpty) return null;
    final parts = (row['song_key'] as String).split(':');
    if (parts.length != 2) return null;
    return Song(
      id: parts[1],
      sourceId: parts[0],
      title: title,
      artist: row['artist'] as String? ?? '',
      coverUrl: row['cover_url'] as String?,
      duration: row['duration'] as int?,
    );
  }

  /// 歌单-歌曲关联行（携带歌曲快照；无快照时元数据列为 null）
  Map<String, Object?> _songRow(
      String playlistId, Playlist playlist, int position) {
    final key = playlist.songKeys[position];
    final snap = playlist.songSnapshots[key];
    return {
      'playlist_id': playlistId,
      'song_key': key,
      'position': position,
      'title': snap?.title,
      'artist': snap?.artist,
      'cover_url': snap?.coverUrl,
      'duration': snap?.duration,
    };
  }
}
