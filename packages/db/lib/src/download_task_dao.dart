/// 下载任务 DAO 的 SQLite 实现
import 'package:core/core.dart';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class SqfliteDownloadTaskDao implements DownloadTaskDao {
  final DatabaseHelper _helper;

  SqfliteDownloadTaskDao(this._helper);

  Future<Database> get _db => _helper.getDatabase();

  @override
  Future<void> upsert(DownloadTask task) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final values = <String, Object?>{
      'song_key': task.songKey,
      'status': task.status.name,
      'progress': task.progress,
      'url': task.url,
      'local_path': task.localPath,
      'error': task.error,
      'updated_at': now,
    };
    final updated = await db.update(
      'download_tasks',
      values,
      where: 'song_key = ?',
      whereArgs: [task.songKey],
    );
    if (updated == 0) {
      values['created_at'] = now;
      await db.insert(
        'download_tasks',
        values,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  @override
  Future<List<DownloadTask>> getAll() async {
    final db = await _db;
    final rows = await db.query('download_tasks', orderBy: 'created_at ASC');
    return rows.map(_fromRow).toList();
  }

  DownloadTask _fromRow(Map<String, Object?> row) {
    final name = row['status'] as String? ?? '';
    final status = DownloadStatus.values.firstWhere(
      (s) => s.name == name,
      orElse: () => DownloadStatus.failed,
    );
    return DownloadTask(
      songKey: row['song_key'] as String,
      url: row['url'] as String?,
      status: status,
      progress: (row['progress'] as num?)?.toDouble() ?? 0,
      localPath: row['local_path'] as String?,
      error: row['error'] as String?,
    );
  }

  @override
  Future<void> delete(String songKey) async {
    final db = await _db;
    await db.delete('download_tasks', where: 'song_key = ?', whereArgs: [songKey]);
  }

  @override
  Future<void> clearByStatus(Set<DownloadStatus> statuses) async {
    if (statuses.isEmpty) return;
    final db = await _db;
    final names = statuses.map((s) => s.name).toList();
    final placeholders = List.filled(names.length, '?').join(',');
    await db.delete(
      'download_tasks',
      where: 'status IN ($placeholders)',
      whereArgs: names,
    );
  }
}
