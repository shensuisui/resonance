/// LocalSnapshotApplier 测试
///
/// 覆盖四条实现约定：
///   1. favorites 以合并结果为全集（本机多出来的删除）；
///   2. songs 只补缺 + 更新元数据，不动 playUrl/localPath；
///   3. 歌单同名沿用本机 id，progress.queueId 跟着重映射；
///   4. settings 只动白名单键（scan_dir 等设备本地项不受影响）。

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync/sync.dart';

/// 构造一份只含指定实体的快照
SyncSnapshot _snap(Map<String, List<SyncRecord>> entities) => SyncSnapshot(
      version: 1,
      updatedAt: 1000,
      writer: 'remote',
      entities: entities,
    );

void main() {
  late InMemoryDatabaseProvider db;

  setUp(() {
    db = InMemoryDatabaseProvider();
  });

  test('favorites：合并结果是全集，本机多出来的被删除', () async {
    await db.favoritesDao.addFavorite('s:a', 1);
    await db.favoritesDao.addFavorite('s:b', 2);

    await LocalSnapshotApplier(db: db).apply(_snap(<String, List<SyncRecord>>{
      SyncEntity.favorites: <SyncRecord>[
        const SyncRecord(
          key: 's:b',
          updatedAt: 2,
          deviceId: 'r',
          data: <String, Object?>{'songKey': 's:b', 'time': 2},
        ),
        const SyncRecord(
          key: 's:c',
          updatedAt: 3,
          deviceId: 'r',
          data: <String, Object?>{'songKey': 's:c', 'time': 3},
        ),
      ],
    }));

    // 顺序由 DAO 决定，这里只关心集合内容（本机多出来的 s:a 必须被删）
    expect(
      (await db.favoritesDao.getAllFavoriteKeys()).toSet(),
      <String>{'s:b', 's:c'},
    );
  });

  test('songs：已有曲只更新元数据，地址类字段保持本机', () async {
    await db.songDao.insertSong(const Song(
      id: '1',
      sourceId: 's',
      title: '旧标题',
      artist: '旧歌手',
      playUrl: 'https://local/fresh.mp3',
      localPath: '/tmp/a.mp3',
    ));

    await LocalSnapshotApplier(db: db).apply(_snap(<String, List<SyncRecord>>{
      SyncEntity.songs: <SyncRecord>[
        const SyncRecord(
          key: 's:1',
          updatedAt: 5,
          deviceId: 'r',
          data: <String, Object?>{
            'id': '1',
            'sourceId': 's',
            'title': '新标题',
            'artist': '新歌手',
            'playUrl': 'https://remote/stale.mp3',
          },
        ),
        const SyncRecord(
          key: 's:2',
          updatedAt: 6,
          deviceId: 'r',
          data: <String, Object?>{
            'id': '2',
            'sourceId': 's',
            'title': '新增曲',
            'artist': '歌手',
            'playUrl': 'https://remote/x.mp3',
          },
        ),
      ],
    }));

    final one = await db.songDao.getSong('1', 's');
    expect(one!.title, '新标题');
    expect(one.playUrl, 'https://local/fresh.mp3'); // 不被远端覆盖
    expect(one.localPath, '/tmp/a.mp3'); // 设备本地字段保留

    final two = await db.songDao.getSong('2', 's');
    expect(two, isNotNull);
    expect(two!.title, '新增曲');
    expect(two.playUrl, isNull); // 新曲不落远端地址，交给本机重新解析
  });

  test('歌单同名沿用本机 id，progress.queueId 跟着重映射', () async {
    final now = DateTime.now();
    await db.playlistDao.insertPlaylist(Playlist(
      id: 'local-p',
      name: '夜行',
      songKeys: const <String>['s:1'],
      createdTime: now,
      modifiedTime: now,
    ));
    await db.playProgressDao.upsert(PlayProgress(
      queueKind: 'playlist',
      queueId: 'local-p',
      songKey: 's:1',
      positionMs: 111,
      updatedAt: 1,
    ));

    await LocalSnapshotApplier(db: db).apply(_snap(<String, List<SyncRecord>>{
      SyncEntity.playlists: <SyncRecord>[
        const SyncRecord(
          key: '夜行',
          updatedAt: 10,
          deviceId: 'r',
          data: <String, Object?>{
            'id': 'remote-p',
            'name': '夜行',
            'songKeys': <String>['s:1', 's:2'],
            'snapshots': <String, Object?>{
              's:1': <String, Object?>{'title': 'T1', 'artist': 'A1'},
            },
          },
        ),
      ],
      SyncEntity.progress: <SyncRecord>[
        const SyncRecord(
          key: 'playlist|remote-p',
          updatedAt: 10,
          deviceId: 'r',
          data: <String, Object?>{
            'queueKind': 'playlist',
            'queueId': 'remote-p',
            'songKey': 's:2',
            'positionMs': 222,
            'updatedAt': 10,
          },
        ),
      ],
    }));

    final playlist = await db.playlistDao.getPlaylist('local-p');
    expect(playlist, isNotNull);
    expect(playlist!.songKeys, <String>['s:1', 's:2']);

    expect(await db.playProgressDao.get('playlist', 'remote-p'), isNull);
    final mapped = await db.playProgressDao.get('playlist', 'local-p');
    expect(mapped, isNotNull);
    expect(mapped!.positionMs, 222);
  });

  test('settings：只动白名单键，设备本地项不受影响', () async {
    await db.settingsDao.set('theme_mode', 'dark');
    await db.settingsDao.set('scan_dir', '/music');

    await LocalSnapshotApplier(db: db).apply(_snap(<String, List<SyncRecord>>{
      SyncEntity.settings: <SyncRecord>[
        const SyncRecord(
          key: 'theme_mode',
          updatedAt: 10,
          deviceId: 'r',
          data: <String, Object?>{'key': 'theme_mode', 'value': 'light'},
        ),
        const SyncRecord(
          key: 'volume',
          updatedAt: 11,
          deviceId: 'r',
          data: <String, Object?>{'key': 'volume', 'value': '0.5'},
        ),
      ],
    }));

    expect(await db.settingsDao.get('theme_mode'), 'light');
    expect(await db.settingsDao.get('volume'), '0.5');
    expect(await db.settingsDao.get('scan_dir'), '/music'); // 设备本地项保留
  });
}
