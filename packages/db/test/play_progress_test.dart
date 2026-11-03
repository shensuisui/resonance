/// 播放进度持久化测试（play_progress 表）
///
/// 为什么要有这张表：关闭 App 后要从上次的队列/曲目/进度继续，
/// 而且歌单详情要能「继续播放」——必须按队列分别记住听到哪。
///
/// 覆盖：
///   ① 写入后能读回（同一队列）；
///   ② 同一队列反复写只留最新一条（覆盖，不是插入新行）；
///   ③ 不同队列互不干扰（歌单 A / 歌单 B / 最近播放）；
///   ④ 删除（歌单被删时清进度）；
///   ⑤ getAll 按更新时间倒序（启动时挑"上次活跃队列"）。
///
/// 数据来源：sqflite_common_ffi 的内存库，不依赖真实文件。
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:db/db.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';

/// 测试用数据库助手（内存库）
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

  group('PlayProgressDao', () {
    test('写入后读回同一队列的进度', () async {
      final dao = provider.playProgressDao;
      await dao.upsert(const PlayProgress(
        queueKind: 'playlist',
        queueId: 'p1',
        songKey: 'gequbao:61636',
        positionMs: 192000,
        updatedAt: 1000,
      ));

      final got = await dao.get('playlist', 'p1');
      expect(got, isNotNull);
      expect(got!.songKey, 'gequbao:61636');
      expect(got.positionMs, 192000);
      expect(got.identity, 'playlist:p1');
    });

    test('同一队列反复写只留最新一条（覆盖而非新增行）', () async {
      final dao = provider.playProgressDao;
      for (var i = 0; i < 5; i++) {
        await dao.upsert(PlayProgress(
          queueKind: 'playlist',
          queueId: 'p1',
          songKey: 'song',
          positionMs: i * 1000,
          updatedAt: 1000 + i,
        ));
      }

      final got = await dao.get('playlist', 'p1');
      expect(got!.positionMs, 4000, reason: '最后一次写入生效');
      expect((await dao.getAll()).length, 1, reason: '不能留 5 行垃圾');
    });

    test('不同队列互不干扰', () async {
      final dao = provider.playProgressDao;
      await dao.upsert(const PlayProgress(
          queueKind: 'playlist',
          queueId: 'a',
          songKey: 's1',
          positionMs: 1000,
          updatedAt: 1));
      await dao.upsert(const PlayProgress(
          queueKind: 'playlist',
          queueId: 'b',
          songKey: 's2',
          positionMs: 2000,
          updatedAt: 2));
      await dao.upsert(const PlayProgress(
          queueKind: 'recent',
          songKey: 's3',
          positionMs: 3000,
          updatedAt: 3));

      expect((await dao.get('playlist', 'a'))!.positionMs, 1000);
      expect((await dao.get('playlist', 'b'))!.positionMs, 2000);
      expect((await dao.get('recent', ''))!.positionMs, 3000);
      expect(await dao.get('liked', ''), isNull, reason: '没写过的队列应当是 null');
    });

    test('删除只删指定队列', () async {
      final dao = provider.playProgressDao;
      await dao.upsert(const PlayProgress(
          queueKind: 'playlist',
          queueId: 'a',
          songKey: 's1',
          positionMs: 1000,
          updatedAt: 1));
      final kept = await dao.get('recent', '');
      expect(kept, isNull);

      await dao.upsert(const PlayProgress(
          queueKind: 'recent',
          songKey: 's9',
          positionMs: 500,
          updatedAt: 2));
      await dao.delete('playlist', 'a');

      expect(await dao.get('playlist', 'a'), isNull);
      expect((await dao.get('recent', ''))!.songKey, 's9', reason: '别的队列不受影响');
    });

    test('getAll 按更新时间倒序（启动时挑上次活跃队列）', () async {
      final dao = provider.playProgressDao;
      await dao.upsert(const PlayProgress(
          queueKind: 'playlist',
          queueId: 'old',
          songKey: 's1',
          positionMs: 1,
          updatedAt: 100));
      await dao.upsert(const PlayProgress(
          queueKind: 'recent',
          songKey: 's2',
          positionMs: 2,
          updatedAt: 900));

      final all = await dao.getAll();
      expect(all.length, 2);
      expect(all.first.queueKind, 'recent', reason: '最近更新的排最前');
    });
  });
group('老库升级（缺新表）', () {
    test('已存在的库打开后自动补建 play_progress，且存量数据不动', () async {
      // 用真实文件库模拟"用户已经装过 App"的老库：先建好、删掉新表、关掉
      final dir = Directory.systemTemp.createTempSync('resonance_db_');
      final path = p.join(dir.path, 'resonance.db');
      try {
        final old = DatabaseHelper(customDbPath: path);
        final db = await old.getDatabase();
        await db.insert('settings', {
          'key': 'theme_mode',
          'value': 'light',
          'updated_at': 1,
        });
        await db.execute('DROP TABLE play_progress');
        await old.close();

        // 重新打开（等价于用户升级后启动）：新表必须被补上
        final reopened = DatabaseHelper(customDbPath: path);
        final db2 = await reopened.getDatabase();
        final rows = await db2.query('sqlite_master',
            where: "type = 'table' AND name = 'play_progress'");
        expect(rows, isNotEmpty, reason: '老库也必须拿到新表，否则进度一条都写不进去');

        // 只加表、不动数据：原来的设置还在
        final setting = await db2.query('settings',
            where: 'key = ?', whereArgs: ['theme_mode']);
        expect(setting.first['value'], 'light');
        await reopened.close();
      } finally {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  });
}