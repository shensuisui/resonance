/// 端到端：同一份数据「备份导入」与「云同步」结果一致
///
/// 证明两条搬运路径共用 portable 的 Reader/Applier/Merger 后语义收敛：
///   A --云同步--> C（远端拉取）
///   A --备份导出--> B（本地导入）
/// 断言 B 与 C 的收藏/歌单/设置/歌曲集合一致。
library;

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portable/portable.dart';
import 'package:sync/sync.dart';

/// 内存 Dav（与 sync_engine_test 同构）
class InMemoryDav implements DavClient {
  final Map<String, List<int>> files = <String, List<int>>{};
  @override
  Future<List<DavEntry>> list(String path) async {
    final prefix = path.endsWith('/') ? path : '$path/';
    final seen = <String>{};
    final out = <DavEntry>[];
    for (final entry in files.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final rest = entry.key.substring(prefix.length);
      if (rest.isEmpty) continue;
      final seg = rest.split('/').first;
      if (!seen.add(seg)) continue;
      final isDir = rest.contains('/');
      out.add(DavEntry(
          path: '$prefix$seg', isDirectory: isDir, size: isDir ? null : entry.value.length));
    }
    return out;
  }

  @override
  Future<List<int>?> read(String path) async => files[path];
  @override
  Future<void> write(String path, List<int> bytes, {String? ifMatch}) async =>
      files[path] = List<int>.from(bytes);
  @override
  Future<void> delete(String path) async =>
      files.removeWhere((k, _) => k == path || k.startsWith('$path/'));
  @override
  Future<void> mkdir(String path) async {}
}

/// 造一台设备
({SyncEngine engine, InMemoryDatabaseProvider db}) device(String id, InMemoryDav dav) {
  final db = InMemoryDatabaseProvider();
  return (
    engine: SyncEngine(
      dav: dav,
      db: db,
      state: MemorySyncStateStore(),
      deviceId: id,
      deviceName: id,
    ),
    db: db,
  );
}

Song song(String sourceId, String id, String title, String artist) =>
    Song(id: id, sourceId: sourceId, title: title, artist: artist, duration: 180);

void main() {
  test('备份导入结果 == 云同步结果（收藏/歌单/设置/歌曲）', () async {
    final dav = InMemoryDav();
    final a = device('A', dav);

    // 种子数据（A）
    await a.db.songDao.insertSong(song('gequbao', '1', '素颜', '许嵩'));
    await a.db.playlistDao.insertPlaylist(Playlist(
      id: 'p1',
      name: '夜行',
      songKeys: const <String>['gequbao:1'],
      songSnapshots: <String, Song>{
        'gequbao:1': song('gequbao', '1', '素颜', '许嵩'),
      },
      createdTime: DateTime(2026, 11, 1),
      modifiedTime: DateTime(2026, 11, 1),
    ));
    await a.db.favoritesDao.addFavorite('gequbao:1', 1000, title: '素颜');
    await a.db.settingsDao.set('theme_mode', 'dark');
    const subs = '[{"url":"https://example.com/rule.json","sourceId":"sub1","alias":"订阅A","rule":"{\"source\":{\"id\":\"sub1\",\"name\":\"订阅源\"}}"}]';
    await a.db.settingsDao.set('subscriptions', subs);

    // 路径一：云同步 A → C
    await a.engine.sync(now: DateTime(2026, 11, 22, 1));
    final c = device('C', dav);
    await c.engine.sync(now: DateTime(2026, 11, 22, 2));

    // 路径二：备份 A → B
    final doc = await BackupService(db: a.db, deviceId: 'A')
        .exportAll(now: DateTime(2026, 11, 22, 3));
    expect(doc.entities[SyncEntity.songs], isNotNull, reason: '备份应含 songs 维度');
    final b = device('B', dav); // 仅借 db，不参与同步
    await BackupService(db: b.db, deviceId: 'B').importDocument(doc);

    // 对比：收藏
    final favB = (await b.db.favoritesDao.getAllFavoriteKeys())..sort();
    final favC = (await c.db.favoritesDao.getAllFavoriteKeys())..sort();
    expect(favB, favC);
    expect(favB, <String>['gequbao:1']);

    // 对比：歌单（id/name/songKeys）
    final plB = (await b.db.playlistDao.getAllPlaylists()).map((p) => '${p.id}|${p.name}|${p.songKeys.join(",")}').toList()..sort();
    final plC = (await c.db.playlistDao.getAllPlaylists()).map((p) => '${p.id}|${p.name}|${p.songKeys.join(",")}').toList()..sort();
    expect(plB, plC);
    expect(plB.single, 'p1|夜行|gequbao:1');

    // 对比：设置
    expect(await b.db.settingsDao.get('theme_mode'),
        await c.db.settingsDao.get('theme_mode'));
    // 订阅（含规则内容）默认随备份与同步
    expect(await b.db.settingsDao.get('subscriptions'), subs);
    expect(await c.db.settingsDao.get('subscriptions'), subs);

    // 对比：歌曲索引
    expect((await b.db.songDao.getAllSongRecords()).length,
        (await c.db.songDao.getAllSongRecords()).length);
  });
}
