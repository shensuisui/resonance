/// 最近播放「移除单条」的数据库测试
///
/// 用户要求：最近播放列表里能移除一条（重复条目先不管）。
/// 移除只删 recent_plays 这一行 —— 不能顺手把缓存/收藏/歌单里的东西删掉。
library;

import 'package:core/core.dart';
import 'package:db/db.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存库助手
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

  test('deleteRecentPlay 只删指定那一条', () async {
    final dao = provider.recentPlaysDao;
    await dao.insertOrUpdateRecentPlay('s:a', 100, title: '甲');
    await dao.insertOrUpdateRecentPlay('s:b', 200, title: '乙');
    await dao.insertOrUpdateRecentPlay('s:c', 300, title: '丙');

    await dao.deleteRecentPlay('s:b');

    final records = await dao.getRecentPlayRecords();
    expect(records.map((r) => r.songKey), ['s:c', 's:a'],
        reason: '只删 s:b，其它两条保留且仍按时间倒序');
  });

  test('删不存在的 key 不报错（幂等）', () async {
    await provider.recentPlaysDao.deleteRecentPlay('nope:x');
    expect(await provider.recentPlaysDao.getRecentPlayRecords(), isEmpty);
  });

  test('移除记录不影响歌曲表里的同一首歌', () async {
    await provider.songDao.insertSong(
      const Song(id: 'a', sourceId: 's', title: '甲', artist: ''),
    );
    await provider.recentPlaysDao.insertOrUpdateRecentPlay('s:a', 100, title: '甲');

    await provider.recentPlaysDao.deleteRecentPlay('s:a');

    expect(await provider.recentPlaysDao.getRecentPlayRecords(), isEmpty);
    expect(await provider.songDao.getSong('a', 's'), isNotNull,
        reason: '歌曲元数据不该被这次移除牵连');
  });
}
