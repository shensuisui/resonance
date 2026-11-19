/// 同步用的读取接口测试
///
/// 覆盖 getSongsUpdatedAt 之外的另两个「全量 + 时间戳」读取：
///   * SongDao.getAllSongRecords：含 updated_at；
///   * SettingsDao.getAllEntries：含 updated_at。
///
/// 用 sqflite_common_ffi 内存库，不依赖真实文件系统。

import 'package:core/core.dart';
import 'package:db/db.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存数据库助手
DatabaseHelper _newInMemoryHelper() {
  initSqfliteForPlatform();
  return DatabaseHelper(customDbPath: getInMemoryDatabasePath());
}

void main() {
  late SqfliteDatabaseProvider provider;

  setUp(() async {
    provider = SqfliteDatabaseProvider.withHelper(_newInMemoryHelper());
    await provider.initialize();
  });

  tearDown(() async {
    await provider.close();
  });

  test('getAllSongRecords 返回全部歌曲并带非 0 更新时间', () async {
    await provider.songDao
        .insertSong(const Song(id: '1', sourceId: 's', title: 'A', artist: 'X'));
    await provider.songDao
        .insertSong(const Song(id: '2', sourceId: 's', title: 'B', artist: 'Y'));

    final records = await provider.songDao.getAllSongRecords();
    expect(records.length, 2);
    for (final r in records) {
      expect(r.updatedAt, greaterThan(0));
    }
    expect(records.map((r) => r.song.title).toSet(), {'A', 'B'});
  });

  test('getAllEntries 返回全部设置并带非 0 更新时间', () async {
    await provider.settingsDao.set('theme_mode', 'dark');
    await provider.settingsDao.set('volume', '0.5');

    final entries = await provider.settingsDao.getAllEntries();
    expect(entries.length, 2);
    final byKey = {for (final e in entries) e.key: e};
    expect(byKey['theme_mode']!.value, 'dark');
    expect(byKey['volume']!.value, '0.5');
    for (final e in entries) {
      expect(e.updatedAt, greaterThan(0));
    }
  });
}
