/// LocalSnapshotReader 测试
///
/// 覆盖：
///   1. 六类实体都能从内存 DAO 读成记录（键/时间戳/数据齐全）；
///   2. songs 剔除 local_path 与 lyric 正文（设备本地/可回源）；
///   3. settings 只保留白名单键（source_enabled_ 前缀参与）；
///   4. 基线里同 key+updatedAt 的记录沿用其 deviceId（平手判定稳定）。
///
/// 不依赖真实网络/文件：用 core 的内存 DatabaseProvider。

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync/sync.dart';

/// 构造一张测试歌单
Playlist _playlist(String id, String name, List<String> keys) {
  final now = DateTime.now();
  return Playlist(
    id: id,
    name: name,
    songKeys: keys,
    songSnapshots: <String, Song>{
      keys.first: Song(
        id: keys.first.split(':')[1],
        sourceId: keys.first.split(':')[0],
        title: '快照标题',
        artist: '快照歌手',
      ),
    },
    createdTime: now,
    modifiedTime: now,
  );
}

void main() {
  late InMemoryDatabaseProvider db;

  setUp(() {
    db = InMemoryDatabaseProvider();
  });

  test('六类实体都能读成快照记录', () async {
    await db.songDao.insertSong(const Song(
      id: '1',
      sourceId: 's',
      title: '歌',
      artist: '手',
      localPath: '/tmp/a.mp3',
      lyric: '[00:00]歌词',
      duration: 100,
    ));
    await db.playlistDao.insertPlaylist(_playlist('p1', '夜行', ['s:1']));
    await db.favoritesDao.addFavorite('s:1', 1000, title: '歌', artist: '手');
    await db.recentPlaysDao
        .insertOrUpdateRecentPlay('s:1', 2000, title: '歌', artist: '手');
    await db.playProgressDao.upsert(const PlayProgress(
      queueKind: 'playlist',
      queueId: 'p1',
      songKey: 's:1',
      positionMs: 30000,
      updatedAt: 3000,
    ));

    final snapshot = await LocalSnapshotReader(db: db, deviceId: 'me')
        .read(version: 1, writer: 'me');

    expect(snapshot.version, 1);
    expect(snapshot.recordsOf(SyncEntity.songs).single.key, 's:1');
    expect(snapshot.recordsOf(SyncEntity.playlists).single.key, '夜行');
    expect(snapshot.recordsOf(SyncEntity.favorites).single.key, 's:1');
    expect(snapshot.recordsOf(SyncEntity.recent).single.key, 's:1');
    expect(
      snapshot.recordsOf(SyncEntity.progress).single.key,
      'playlist|p1',
    );
    // 时间戳来自各自的时间列
    expect(snapshot.recordsOf(SyncEntity.favorites).single.updatedAt, 1000);
    expect(snapshot.recordsOf(SyncEntity.recent).single.updatedAt, 2000);
    expect(snapshot.recordsOf(SyncEntity.progress).single.updatedAt, 3000);
  });

  test('songs 剔除 local_path 与 lyric 正文', () async {
    await db.songDao.insertSong(const Song(
      id: '1',
      sourceId: 's',
      title: '歌',
      artist: '手',
      localPath: '/tmp/a.mp3',
      lyric: '[00:00]歌词',
      lyricUrl: 'https://x/l.lrc',
    ));
    final rec = (await LocalSnapshotReader(db: db, deviceId: 'me')
            .read(version: 1, writer: 'me'))
        .recordsOf(SyncEntity.songs)
        .single;
    expect(rec.data.containsKey('localPath'), isFalse);
    expect(rec.data.containsKey('lyric'), isFalse);
    // 歌词地址保留（可回源），正文不带
    expect(rec.data['lyricUrl'], 'https://x/l.lrc');
  });

  test('settings 只保留白名单键（含 source_enabled_ 前缀）', () async {
    await db.settingsDao.set('theme_mode', 'dark');
    await db.settingsDao.set('source_enabled_a', '1');
    await db.settingsDao.set('scan_dir', '/music');
    await db.settingsDao.set('play_device', '本机扬声器');
    await db.settingsDao.set('sync_enabled', 'true');

    final recs = (await LocalSnapshotReader(db: db, deviceId: 'me')
            .read(version: 1, writer: 'me'))
        .recordsOf(SyncEntity.settings);
    final keys = recs.map((r) => r.key).toSet();
    expect(keys, containsAll(<String>['theme_mode', 'source_enabled_a']));
    expect(keys, isNot(contains('scan_dir')));
    expect(keys, isNot(contains('play_device')));
    expect(keys, isNot(contains('sync_enabled')));
  });

  test('基线中同 key+updatedAt 的记录沿用其 deviceId', () async {
    await db.favoritesDao.addFavorite('s:1', 1234);
    final baseline = SyncSnapshot(
      version: 1,
      updatedAt: 0,
      writer: 'other',
      entities: <String, List<SyncRecord>>{
        SyncEntity.favorites: <SyncRecord>[
          const SyncRecord(
            key: 's:1',
            updatedAt: 1234,
            deviceId: 'device-other',
            data: <String, Object?>{},
          ),
        ],
      },
    );
    final rec = (await LocalSnapshotReader(db: db, deviceId: 'me')
            .read(version: 1, writer: 'me', baseline: baseline))
        .recordsOf(SyncEntity.favorites)
        .single;
    expect(rec.deviceId, 'device-other');
  });
}
