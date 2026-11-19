/// SettingsDao 的 SQLite 实现
///
/// 简单的 key-value 存储，带 updated_at 时间戳
/// 用于多设备同步预留。

import 'package:core/core.dart';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class SqfliteSettingsDao implements SettingsDao {
  final DatabaseHelper _helper;

  /// 写变更总线（可空：单测可不接）
  final DbChangeBus? _bus;

  SqfliteSettingsDao(this._helper, {DbChangeBus? changeBus}) : _bus = changeBus;

  /// 通知同步层：设置变了
  void _emit() => _bus?.emit(DbEntity.settings);

  Future<Database> get _db => _helper.getDatabase();

  @override
  Future<String?> get(String key) async {
    final db = await _db;
    final rows = await db.query('settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  @override
  Future<void> set(String key, String value) async {
    final db = await _db;
    await db.insert('settings', {
      'key': key,
      'value': value,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _emit();
  }

  @override
  Future<Map<String, String>> getAll() async {
    final db = await _db;
    final rows = await db.query('settings');
    return {for (final r in rows) r['key'] as String: r['value'] as String? ?? ''};
  }

  @override
  Future<void> delete(String key) async {
    final db = await _db;
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
    _emit();
  }
}
