/// BackupService v2 单测（真实内存 DAO，不 mock）
///
/// 覆盖：导出范围/白名单、merge 幂等与 updatedAt 判胜、overwrite 清空、
/// 设备本地分区可选、songs 写回（导入后能搜到）。
library;

import 'package:core/core.dart';
import 'package:portable/portable.dart';
import 'package:test/test.dart';

Song song(String sourceId, String id, String title, String artist) => Song(
      id: id,
      sourceId: sourceId,
      title: title,
      artist: artist,
      duration: 200000,
    );

Future<InMemoryDatabaseProvider> seed() async {
  final db = InMemoryDatabaseProvider();
  await db.initialize();
  final now = DateTime(2026, 11, 12, 20, 30);
  await db.songDao.insertSong(song('gequbao', '1', '素颜', '许嵩'));
  await db.playlistDao.insertPlaylist(Playlist(
    id: 'p1',
    name: '夜行',
    songKeys: const <String>['gequbao:1'],
    songSnapshots: <String, Song>{'gequbao:1': song('gequbao', '1', '素颜', '许嵩')},
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
  await db.settingsDao.set('subscriptions', 'https://private/x.json');
  await db.settingsDao.set('scan_dir', 'D:/music');
  return db;
}

void main() {
  test('导出范围：含 songs/歌单/收藏/最近；设置只含可移植键', () async {
    final db = await seed();
    final service = BackupService(db: db, deviceId: 'src');
    final doc = await service.exportAll(now: DateTime(2026, 11, 22));

    expect(doc.entities[SyncEntity.songs]!.length, 1);
    expect(doc.entities[SyncEntity.playlists]!.length, 1);
    expect(doc.entities[SyncEntity.favorites]!.length, 1);
    expect(doc.entities[SyncEntity.recent]!.length, 1);

    final settingsKeys = doc.entities[SyncEntity.settings]!.map((r) => r.key).toSet();
    expect(settingsKeys.contains('theme_mode'), isTrue);
    expect(settingsKeys.contains('source_enabled_gequbao'), isTrue);
    expect(settingsKeys.contains('subscriptions'), isFalse);
    expect(settingsKeys.contains('scan_dir'), isFalse);
    expect(doc.entities.containsKey(kDeviceSettingsEntity), isFalse);
  });

  test('设备本地分区：勾选才导出 scan_dir', () async {
    final db = await seed();
    final doc = await BackupService(db: db, deviceId: 'src')
        .exportAll(includeDeviceSettings: true);
    final keys = doc.entities[kDeviceSettingsEntity]!.map((r) => r.key).toSet();
    expect(keys.contains('scan_dir'), isTrue);
    expect(keys.contains('theme_mode'), isFalse);
  });

  test('merge：导入后数据齐全，重复导入幂等（全部跳过）', () async {
    final src = await seed();
    final doc = await BackupService(db: src, deviceId: 'src').exportAll();

    final dst = InMemoryDatabaseProvider();
    await dst.initialize();
    final service = BackupService(db: dst, deviceId: 'dst');

    final first = await service.importDocument(doc);
    expect(first.of(BackupSection.favorites).added, 1);
    expect(first.of(BackupSection.playlists).added, 1);
    expect(await dst.favoritesDao.isFavorite('gequbao:2'), isTrue);
    expect((await dst.playlistDao.getAllPlaylists()).length, 1);
    expect(await dst.settingsDao.get('theme_mode'), 'dark');
    // songs 写回后可搜到
    expect((await dst.songDao.searchSongs('素颜')).isNotEmpty, isTrue);

    final second = await service.importDocument(doc);
    expect(second.of(BackupSection.favorites).added, 0);
    expect(second.of(BackupSection.favorites).skipped, 1);
    expect(await dst.favoritesDao.getAllFavoriteKeys().then((k) => k.length), 1);
  });

  test('merge：本机更新（updatedAt 更晚）不被旧文件覆盖', () async {
    final src = await seed();
    final doc = await BackupService(db: src, deviceId: 'src').exportAll();

    final dst = InMemoryDatabaseProvider();
    await dst.initialize();
    await dst.favoritesDao.addFavorite('gequbao:2', 9999999999999, title: '本机最新');

    final report = await BackupService(db: dst, deviceId: 'dst')
        .importDocument(doc, sections: <BackupSection>{BackupSection.favorites});
    expect(report.of(BackupSection.favorites).skipped, 1);
    final rec = (await dst.favoritesDao.getAllFavoriteRecords()).single;
    expect(rec.title, '本机最新');
  });

  test('overwrite：收藏先清空再写入（本机多余项被删）', () async {
    final src = await seed();
    final doc = await BackupService(db: src, deviceId: 'src').exportAll();

    final dst = InMemoryDatabaseProvider();
    await dst.initialize();
    await dst.favoritesDao.addFavorite('other:9', 1, title: '旧收藏');

    await BackupService(db: dst, deviceId: 'dst').importDocument(
      doc,
      mode: BackupImportMode.overwrite,
      sections: <BackupSection>{BackupSection.favorites},
    );
    final keys = await dst.favoritesDao.getAllFavoriteKeys();
    expect(keys.contains('other:9'), isFalse);
    expect(keys.contains('gequbao:2'), isTrue);
  });
}
