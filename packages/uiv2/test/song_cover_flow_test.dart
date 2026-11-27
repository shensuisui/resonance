/// 封面链路回归：快照补全 + 队列 hydration + 集合快照刷新
///
/// 场景：搜索快照无封面 → 起播后详情补到封面 → 写 song 表；
/// 但最近播放/收藏是“快照”，若不同步刷新，重启后队列与通知仍无封面。
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/providers/providers.dart';

void main() {
  late InMemoryDatabaseProvider db;
  late ProviderContainer container;

  setUp(() async {
    db = InMemoryDatabaseProvider();
    await db.initialize();
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      recentPlaysServiceProvider.overrideWithValue(
        RecentPlaysService(db.recentPlaysDao),
      ),
    ]);
  });

  tearDown(() => container.dispose());

  test('hydrateSongsFromCache：用 song 表缓存补上队列曲目的封面', () async {
    const snapshot = Song(id: '1', sourceId: 's', title: '幻听', artist: '许嵩');
    await db.songDao.insertSong(const Song(
      id: '1', sourceId: 's', title: '幻听', artist: '许嵩',
      coverUrl: 'https://cover/1.jpg', duration: 273,
    ));

    final hydrated =
        await hydrateSongsFromCache(db.songDao, const <Song>[snapshot]);
    expect(hydrated.single.coverUrl, 'https://cover/1.jpg');
    expect(hydrated.single.title, '幻听');
  });

  test('updateCollections：把封面写回最近播放与收藏快照', () async {
    const bare = Song(id: '1', sourceId: 's', title: '幻听', artist: '许嵩');
    await db.recentPlaysDao.insertOrUpdateRecentPlay('s:1', 1000,
        title: '幻听', artist: '许嵩');
    await db.favoritesDao.addFavorite('s:1', 2000, title: '幻听', artist: '许嵩');

    const enriched = Song(
      id: '1', sourceId: 's', title: '幻听', artist: '许嵩',
      coverUrl: 'https://cover/1.jpg',
    );
    await container
        .read(songMetadataServiceProvider)
        .updateCollections(enriched);

    expect((await db.recentPlaysDao.getRecentPlayRecords()).single.coverUrl,
        'https://cover/1.jpg');
    expect((await db.favoritesDao.getAllFavoriteRecords()).single.coverUrl,
        'https://cover/1.jpg');
    // 原时间戳不被改动（最近播放排序依赖它）
    expect((await db.recentPlaysDao.getRecentPlayRecords()).single.playedAt,
        1000);
    expect(bare.globalKey, 's:1');
  });
}
