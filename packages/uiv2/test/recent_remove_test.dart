/// 最近播放「移除」的状态层测试
///
/// 要求：点行菜单里的「从最近播放移除」后，列表里立刻不再有它，
/// 且数据库里那一行真的没了（用真实 RecentPlaysService + 内存 DAO）。
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/providers/providers.dart';

void main() {
  late ProviderContainer container;
  late InMemoryDatabaseProvider db;

  setUp(() async {
    db = InMemoryDatabaseProvider();
    await db.initialize();
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      recentPlaysServiceProvider
          .overrideWithValue(RecentPlaysService(db.recentPlaysDao)),
    ]);
  });

  tearDown(() => container.dispose());

  test('移除后最近播放列表与数据库都不再有它', () async {
    await db.recentPlaysDao.insertOrUpdateRecentPlay('s:a', 100, title: '甲');
    await db.recentPlaysDao.insertOrUpdateRecentPlay('s:b', 200, title: '乙');

    await container.read(recentProvider.notifier).load();
    expect(container.read(recentSongsProvider).map((s) => s.globalKey),
        ['s:b', 's:a']);

    await container.read(recentProvider.notifier).remove('s:a');

    expect(container.read(recentSongsProvider).map((s) => s.globalKey), ['s:b']);
    final rows = await db.recentPlaysDao.getRecentPlayRecords();
    expect(rows.map((r) => r.songKey), ['s:b'], reason: '数据库那行也要真的删掉');
  });

  test('移除不存在的 key 不抛异常', () async {
    await container.read(recentProvider.notifier).load();
    await container.read(recentProvider.notifier).remove('nope:x');
    expect(container.read(recentSongsProvider), isEmpty);
  });
}
