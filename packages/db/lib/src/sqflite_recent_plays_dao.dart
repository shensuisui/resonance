/// RecentPlaysDao 的 SQLite 实现
///
/// 利用 INSERT OR REPLACE 实现去重+移顶，
/// 利用 played_at DESC 索引实现按时间倒序查询。

import 'package:core/core.dart';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class SqfliteRecentPlaysDao implements RecentPlaysDao {
  final DatabaseHelper _helper;

  SqfliteRecentPlaysDao(this._helper);

  Future<Database> get _db => _helper.getDatabase();

  @override
  Future<void> insertOrUpdateRecentPlay(String songKey, int playedAt) async {
    final db = await _db;
    await db.insert('recent_plays', {
      'song_key': songKey,
      'played_at': playedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<String>> getRecentPlayKeys({int limit = 500}) async {
    final db = await _db;
    final rows = await db.query('recent_plays',
        orderBy: 'played_at DESC', limit: limit);
    return rows.map((r) => r['song_key'] as String).toList();
  }

  @override
  Future<void> cleanOldest(int maxCount) async {
    final db = await _db;
    // 查总数
    final countResult =
        await db.rawQuery('SELECT COUNT(*) as cnt FROM recent_plays');
    final count = countResult.first['cnt'] as int;
    if (count <= maxCount) return;

    // 删除超出上限的最旧记录
    final toDelete = count - maxCount;
    await db.rawDelete(
      'DELETE FROM recent_plays WHERE song_key IN '
      '(SELECT song_key FROM recent_plays ORDER BY played_at ASC LIMIT ?)',
      [toDelete],
    );
  }
}
