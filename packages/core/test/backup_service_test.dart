/// BackupService 单元测试（真实内存 SQLite 实现，不用 mock）
///
/// 测什么：
///   * exportAll 的取出范围（含设置白名单过滤）；
///   * 合并导入的幂等性（重复导入不产生重复数据）；
///   * 同名歌单追加、覆盖模式清空重写；
///   * 白名单外设置被拒绝并给出警告；
///   * 本地曲目回写 songs 表（否则导入的本地歌单「看得见播不了」）。
///
/// 数据来源：InMemoryDatabaseProvider（项目自带的真实 DAO 实现）。
library;

import 'package:core/core.dart';
import 'package:test/test.dart';

/// 造一首歌（快照用）
Song song(String sourceId, String id, String title, String artist) => Song(
      id: id,
      sourceId: sourceId,
      title: title,
      artist: artist,
      duration: 200000,
    );

Future<InMemoryDatabaseProvider> seedDatabase() async {
  final db = InMemoryDatabaseProvider();
  await db.initialize();
  final now = DateTime(2026, 11, 12, 20, 30);

  await db.playlistDao.insertPlaylist(Playlist(
    id: 'p1',
    name: '夜行',
    songKeys: const <String>['gequbao:1'],
    songSnapshots: <String, Song>{'gequbao:1': song('gequbao', '1', '素颜', '许嵩')},
    createdTime: now,
    modifiedTime: now,
  ));
  await db.playlistDao.insertPlaylist(Playlist(
    id: 'p2',
    name: '通勤',
    songKeys: const <String>['fengye:11'],
    createdTime: now,
    modifiedTime: now,
  ));
  await db.favoritesDao.addFavorite('gequbao:2', now.millisecondsSinceEpoch,
      title: '山水之间', artist: '许嵩');
  await db.recentPlaysDao.insertOrUpdateRecentPlay(
      'gequbao:3', now.millisecondsSinceEpoch,
      title: '幻听', artist: '许嵩');
  await db.settingsDao.set('theme_mode', 'dark');
  await db.settingsDao.set('source_enabled_gequbao', '1');
  // 白名单外：订阅地址属于隐私，不能进备份
  await db.settingsDao.set('subscriptions', '[{"url":"https://secret"}]');
  await db.settingsDao.set('some_token', 'abc');
  await db.playProgressDao.upsert(const PlayProgress(
    queueKind: 'playlist',
    queueId: 'p1',
    songKey: 'gequbao:1',
    positionMs: 123000,
    updatedAt: 1690000000000,
  ));
  return db;
}

BackupService serviceFor(InMemoryDatabaseProvider db) => BackupService(
      playlistDao: db.playlistDao,
      favoritesDao: db.favoritesDao,
      recentPlaysDao: db.recentPlaysDao,
      settingsDao: db.settingsDao,
      playProgressDao: db.playProgressDao,
      songDao: db.songDao,
    );

void main() {
  group('exportAll', () {
    test('取出歌单/收藏/最近/进度，设置只保留白名单键', () async {
      final db = await seedDatabase();
      final doc = await serviceFor(db).exportAll();

      expect(doc.playlists.length, 2);
      expect(doc.playlists.first.songs, isNotEmpty);
      expect(doc.playlists.first.songs.first.title, '素颜',
          reason: '快照要一起导出，否则换设备后列表是空白名');
      expect(doc.favorites.single.songKey, 'gequbao:2');
      expect(doc.recent.single.songKey, 'gequbao:3');
      expect(doc.progress.single.positionMs, 123000);

      expect(doc.settings['theme_mode'], 'dark');
      expect(doc.settings['source_enabled_gequbao'], '1');
      expect(doc.settings.containsKey('subscriptions'), isFalse,
          reason: '订阅地址是私有 URL，不能进备份');
      expect(doc.settings.containsKey('some_token'), isFalse);
    });
  });

  group('importDocument · merge', () {
    test('空库导入：五个分区全部新增，再导一次全部跳过（幂等）', () async {
      final source = await seedDatabase();
      final doc = await serviceFor(source).exportAll();

      final target = InMemoryDatabaseProvider();
      await target.initialize();
      final service = serviceFor(target);

      final first = await service.importDocument(doc);
      expect(first.of(BackupSection.playlists).added, 2);
      expect(first.of(BackupSection.favorites).added, 1);
      expect(first.of(BackupSection.recent).added, 1);
      expect(first.of(BackupSection.settings).added, 2);
      expect(first.of(BackupSection.progress).added, 1);

      final second = await service.importDocument(doc);
      expect(second.of(BackupSection.playlists).added, 0,
          reason: '同名歌单 id 由名字派生，重复导入不应产生副本');
      expect(second.of(BackupSection.favorites).added, 0);
      expect(second.of(BackupSection.recent).added, 0);
      expect((await target.playlistDao.getAllPlaylists()).length, 2);
    });

    test('同名歌单追加新歌，不覆盖已有顺序', () async {
      final target = InMemoryDatabaseProvider();
      await target.initialize();
      final now = DateTime(2026, 1, 1);
      await target.playlistDao.insertPlaylist(Playlist(
        id: 'p1',
        name: '夜行',
        songKeys: const <String>['gequbao:1'],
        createdTime: now,
        modifiedTime: now,
      ));

      final doc = BackupDocument(
        exportedAt: now,
        playlists: const <BackupPlaylist>[
          BackupPlaylist(name: '夜行', songs: <BackupSong>[
            BackupSong(songKey: 'gequbao:1', title: '素颜', artist: '许嵩'),
            BackupSong(songKey: 'gequbao:9', title: '新歌', artist: '某人'),
          ]),
        ],
      );

      final report = await serviceFor(target).importDocument(doc);
      expect(report.of(BackupSection.playlists).updated, 1);

      final merged = (await target.playlistDao.getAllPlaylists()).single;
      expect(merged.songKeys, <String>['gequbao:1', 'gequbao:9'],
          reason: '原有顺序在前，新歌追加在后，且已去重');
      expect(merged.songSnapshots['gequbao:9']?.title, '新歌');
    });

    test('merge 模式不覆盖本机已存在的设置键', () async {
      final target = InMemoryDatabaseProvider();
      await target.initialize();
      await target.settingsDao.set('theme_mode', 'light');

      final doc = BackupDocument(
        exportedAt: DateTime(2026, 1, 1),
        settings: <String, String>{'theme_mode': 'dark', 'volume': '0.5'},
      );
      final report = await serviceFor(target).importDocument(doc);
      expect(await target.settingsDao.get('theme_mode'), 'light',
          reason: '本机选择优先');
      expect(await target.settingsDao.get('volume'), '0.5');
      expect(report.of(BackupSection.settings).added, 1);
      expect(report.of(BackupSection.settings).skipped, 1);
    });

    test('白名单外的设置键被拒绝并给出警告', () async {
      final target = InMemoryDatabaseProvider();
      await target.initialize();
      final doc = BackupDocument(
        exportedAt: DateTime(2026, 1, 1),
        settings: <String, String>{
          'theme_mode': 'dark',
          'subscriptions': '[{"url":"https://evil"}]',
        },
      );
      final report = await serviceFor(target).importDocument(doc);
      expect(await target.settingsDao.get('subscriptions'), isNull);
      expect(report.warnings.join(' '), contains('不在白名单'));
    });
  });

  group('importDocument · overwrite', () {
    test('先清空再写入：已有的歌单/收藏/最近都被替换成备份内容', () async {
      final target = await seedDatabase();
      // 备份内容与目标库不同名：覆盖后应只剩备份里的那些
      final doc = BackupDocument(
        exportedAt: DateTime(2026, 1, 1),
        playlists: const <BackupPlaylist>[
          BackupPlaylist(name: '备份歌单', songs: <BackupSong>[
            BackupSong(songKey: 'gequbao:5', title: 'A', artist: 'B'),
          ]),
        ],
        favorites: const <BackupFavorite>[
          BackupFavorite(songKey: 'gequbao:6', time: 1),
        ],
        recent: const <BackupRecent>[
          BackupRecent(songKey: 'gequbao:7', playedAt: 2),
        ],
      );

      final report = await serviceFor(target)
          .importDocument(doc, mode: BackupImportMode.overwrite);
      expect(report.of(BackupSection.playlists).added, 1);

      final playlists = await target.playlistDao.getAllPlaylists();
      expect(playlists.length, 1);
      expect(playlists.single.name, '备份歌单');
      expect((await target.favoritesDao.getAllFavoriteRecords()).length, 1);
      expect((await target.recentPlaysDao.getRecentPlayRecords()).length, 1);
    });
  });

  group('本地曲目回写', () {
    test('local_scan 曲目（带 localPath）导入时写入 songs 表', () async {
      final target = InMemoryDatabaseProvider();
      await target.initialize();
      final doc = BackupDocument(
        exportedAt: DateTime(2026, 1, 1),
        playlists: const <BackupPlaylist>[
          BackupPlaylist(name: '本地', songs: <BackupSong>[
            BackupSong(
              songKey: 'local_scan:imp_1',
              title: '本地歌',
              artist: '我',
              localPath: 'D:/Music/a.mp3',
            ),
          ]),
        ],
      );
      await serviceFor(target).importDocument(doc);
      final stored = await target.songDao.getSong('imp_1', 'local_scan');
      expect(stored, isNotNull, reason: '不写回 songs 表就搜不到/播不了');
      expect(stored!.localPath, 'D:/Music/a.mp3');
    });

    test('远程源曲目（无本地路径）不写 songs 表', () async {
      final target = InMemoryDatabaseProvider();
      await target.initialize();
      final doc = BackupDocument(
        exportedAt: DateTime(2026, 1, 1),
        playlists: const <BackupPlaylist>[
          BackupPlaylist(name: '远程', songs: <BackupSong>[
            BackupSong(songKey: 'gequbao:42', title: '远程歌', artist: 'X'),
          ]),
        ],
      );
      await serviceFor(target).importDocument(doc);
      expect(await target.songDao.getSong('42', 'gequbao'), isNull);
    });
  });
}
