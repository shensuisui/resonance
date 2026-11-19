/// playlist_songs.updated_at 测试
///
/// 锁定云同步依赖的语义：
///   1. 写入歌单后 getSongsUpdatedAt 返回非 0；
///   2. 更新歌单（增删/换序）后时间戳前进；
///   3. 删除歌单后回到 0；
///   4. 空歌单（无曲目行）返回 0。
///
/// 用 sqflite_common_ffi 的内存库，不依赖真实文件系统。

import 'package:core/core.dart';
import 'package:db/db.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存数据库助手（与 sqflite_dao_test 同一模式）
DatabaseHelper _newInMemoryHelper() {
  initSqfliteForPlatform();
  return DatabaseHelper(customDbPath: getInMemoryDatabasePath());
}

/// 构造一张测试歌单
Playlist _playlist(String id, List<String> keys) {
  final now = DateTime.now();
  return Playlist(
    id: id,
    name: '测试歌单',
    songKeys: keys,
    createdTime: now,
    modifiedTime: now,
  );
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

  test('插入歌单后曲目变更时间非 0', () async {
    await provider.playlistDao
        .insertPlaylist(_playlist('p1', ['s:1', 's:2']));
    final ts = await provider.playlistDao.getSongsUpdatedAt('p1');
    expect(ts, greaterThan(0));
  });

  test('更新歌单（增曲）后时间戳前进', () async {
    await provider.playlistDao.insertPlaylist(_playlist('p1', ['s:1']));
    final before = await provider.playlistDao.getSongsUpdatedAt('p1');

    // 毫秒精度：等 2ms 保证时间戳严格前进
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await provider.playlistDao
        .updatePlaylist(_playlist('p1', ['s:1', 's:2']));
    final after = await provider.playlistDao.getSongsUpdatedAt('p1');

    expect(after, greaterThan(before));
  });

  test('删除歌单后曲目变更时间回到 0', () async {
    await provider.playlistDao.insertPlaylist(_playlist('p1', ['s:1']));
    await provider.playlistDao.deletePlaylist('p1');
    expect(await provider.playlistDao.getSongsUpdatedAt('p1'), 0);
  });

  test('不存在的歌单返回 0', () async {
    expect(await provider.playlistDao.getSongsUpdatedAt('missing'), 0);
  });
}
