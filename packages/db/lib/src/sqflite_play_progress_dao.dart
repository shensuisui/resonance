/// 播放进度 DAO 的 SQLite 实现
///
/// 一个队列一行（主键 = 队列种类 + 队列 id），只存"听到哪"，
/// 歌单增删歌不影响这一行 —— 曲目本身每次从真实数据重建。
library;

import 'package:core/core.dart';
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

class SqflitePlayProgressDao implements PlayProgressDao {
  /// 数据库助手
  final DatabaseHelper _helper;

  /// 构造
  SqflitePlayProgressDao(this._helper);

  Future<Database> get _db => _helper.getDatabase();

  @override
  Future<PlayProgress?> get(String queueKind, String queueId) async {
    final db = await _db;
    final rows = await db.query(
      'play_progress',
      where: 'queue_kind = ? AND queue_id = ?',
      whereArgs: [queueKind, queueId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return PlayProgress(
      queueKind: r['queue_kind'] as String,
      queueId: r['queue_id'] as String? ?? '',
      songKey: r['song_key'] as String,
      positionMs: (r['position_ms'] as num?)?.toInt() ?? 0,
      updatedAt: (r['updated_at'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> upsert(PlayProgress progress) async {
    final db = await _db;
    await db.insert(
      'play_progress',
      {
        'queue_kind': progress.queueKind,
        'queue_id': progress.queueId,
        'song_key': progress.songKey,
        'position_ms': progress.positionMs,
        'updated_at': progress.updatedAt,
      },
      // 同一队列只留最新一条：反复播放时不断覆盖，不产生垃圾行
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> delete(String queueKind, String queueId) async {
    final db = await _db;
    await db.delete(
      'play_progress',
      where: 'queue_kind = ? AND queue_id = ?',
      whereArgs: [queueKind, queueId],
    );
  }

  @override
  Future<List<PlayProgress>> getAll() async {
    final db = await _db;
    final rows = await db.query('play_progress', orderBy: 'updated_at DESC');
    return [
      for (final r in rows)
        PlayProgress(
          queueKind: r['queue_kind'] as String,
          queueId: r['queue_id'] as String? ?? '',
          songKey: r['song_key'] as String,
          positionMs: (r['position_ms'] as num?)?.toInt() ?? 0,
          updatedAt: (r['updated_at'] as num?)?.toInt() ?? 0,
        ),
    ];
  }
}
