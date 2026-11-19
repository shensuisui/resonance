/// 本地 → 快照：从 DB 读出各实体，组装 [SyncSnapshot]
///
/// 只负责「读」；合并与写回分别在 merge.dart / applier 里做。
/// 设备本地字段在组装时被剔除（songs.local_path / songs.lyric）。
library;

import 'package:core/core.dart';

import 'snapshot.dart';
import 'sync_settings_keys.dart';

/// 从 DB 组装快照
class LocalSnapshotReader {
  /// 数据库提供者（core 抽象）
  final DatabaseProvider db;

  /// 本机设备 id（写入记录用的 writer/deviceId）
  final String deviceId;

  /// 构造
  const LocalSnapshotReader({required this.db, required this.deviceId});

  /// 组装快照
  ///
  /// [baseline] 为「上次同步基线」：同 key 同 updatedAt 的记录沿用其 deviceId，
  /// 让跨轮次的平手判定保持稳定；否则用本机 deviceId。
  Future<SyncSnapshot> read({
    required int version,
    required String writer,
    SyncSnapshot? baseline,
    DateTime? now,
  }) async {
    final entities = <String, List<SyncRecord>>{
      SyncEntity.songs: await _readSongs(baseline),
      SyncEntity.playlists: await _readPlaylists(baseline),
      SyncEntity.favorites: await _readFavorites(baseline),
      SyncEntity.recent: await _readRecent(baseline),
      SyncEntity.progress: await _readProgress(baseline),
      SyncEntity.settings: await _readSettings(baseline),
    };
    return SyncSnapshot(
      version: version,
      updatedAt: (now ?? DateTime.now()).millisecondsSinceEpoch,
      writer: writer,
      entities: entities,
      tombstones: const <Tombstone>[],
    );
  }

  /// 记录 deviceId：基线里同 key+updatedAt 则沿用，否则本机
  String _deviceOf(
    String entity,
    String key,
    int updatedAt,
    SyncSnapshot? baseline,
  ) {
    final list = baseline?.entities[entity];
    if (list != null) {
      for (final r in list) {
        if (r.key == key && r.updatedAt == updatedAt) return r.deviceId;
      }
    }
    return deviceId;
  }

  Future<List<SyncRecord>> _readSongs(SyncSnapshot? baseline) async {
    final records = await db.songDao.getAllSongRecords();
    return <SyncRecord>[
      for (final item in records)
        SyncRecord(
          key: item.song.globalKey,
          updatedAt: item.updatedAt,
          deviceId: _deviceOf(
              SyncEntity.songs, item.song.globalKey, item.updatedAt, baseline),
          data: <String, Object?>{
            'id': item.song.id,
            'sourceId': item.song.sourceId,
            'title': item.song.title,
            'artist': item.song.artist,
            'album': item.song.album,
            'coverUrl': item.song.coverUrl,
            'duration': item.song.duration,
            'playUrl': item.song.playUrl,
            'lyricUrl': item.song.lyricUrl,
            'extra': item.song.extra,
          },
        ),
    ];
  }

  Future<List<SyncRecord>> _readPlaylists(SyncSnapshot? baseline) async {
    final playlists = await db.playlistDao.getAllPlaylists();
    final out = <SyncRecord>[];
    for (final p in playlists) {
      final songsUpdatedAt = await db.playlistDao.getSongsUpdatedAt(p.id);
      final updatedAt = p.modifiedTime.millisecondsSinceEpoch > songsUpdatedAt
          ? p.modifiedTime.millisecondsSinceEpoch
          : songsUpdatedAt;
      out.add(SyncRecord(
        key: p.name,
        updatedAt: updatedAt,
        deviceId: _deviceOf(SyncEntity.playlists, p.name, updatedAt, baseline),
        data: <String, Object?>{
          'id': p.id,
          'name': p.name,
          'songKeys': p.songKeys,
          'snapshots': <String, Object?>{
            for (final e in p.songSnapshots.entries)
              e.key: <String, Object?>{
                'title': e.value.title,
                'artist': e.value.artist,
                'coverUrl': e.value.coverUrl,
                'duration': e.value.duration,
              },
          },
        },
      ));
    }
    return out;
  }

  Future<List<SyncRecord>> _readFavorites(SyncSnapshot? baseline) async {
    final records = await db.favoritesDao.getAllFavoriteRecords();
    return <SyncRecord>[
      for (final f in records)
        SyncRecord(
          key: f.songKey,
          updatedAt: f.time,
          deviceId: _deviceOf(SyncEntity.favorites, f.songKey, f.time, baseline),
          data: <String, Object?>{
            'songKey': f.songKey,
            'time': f.time,
            'title': f.title,
            'artist': f.artist,
            'coverUrl': f.coverUrl,
          },
        ),
    ];
  }

  Future<List<SyncRecord>> _readRecent(SyncSnapshot? baseline) async {
    final records = await db.recentPlaysDao.getRecentPlayRecords(limit: 500);
    return <SyncRecord>[
      for (final r in records)
        SyncRecord(
          key: r.songKey,
          updatedAt: r.playedAt,
          deviceId:
              _deviceOf(SyncEntity.recent, r.songKey, r.playedAt, baseline),
          data: <String, Object?>{
            'songKey': r.songKey,
            'playedAt': r.playedAt,
            'title': r.title,
            'artist': r.artist,
            'coverUrl': r.coverUrl,
          },
        ),
    ];
  }

  Future<List<SyncRecord>> _readProgress(SyncSnapshot? baseline) async {
    final records = await db.playProgressDao.getAll();
    return <SyncRecord>[
      for (final p in records)
        SyncRecord(
          key: '${p.queueKind}|${p.queueId}',
          updatedAt: p.updatedAt,
          deviceId: _deviceOf(
              SyncEntity.progress, '${p.queueKind}|${p.queueId}', p.updatedAt, baseline),
          data: <String, Object?>{
            'queueKind': p.queueKind,
            'queueId': p.queueId,
            'songKey': p.songKey,
            'positionMs': p.positionMs,
            'updatedAt': p.updatedAt,
          },
        ),
    ];
  }

  Future<List<SyncRecord>> _readSettings(SyncSnapshot? baseline) async {
    final entries = await db.settingsDao.getAllEntries();
    return <SyncRecord>[
      for (final s in entries)
        if (SyncSettingsKeys.isSyncable(s.key))
          SyncRecord(
            key: s.key,
            updatedAt: s.updatedAt,
            deviceId:
                _deviceOf(SyncEntity.settings, s.key, s.updatedAt, baseline),
            data: <String, Object?>{'key': s.key, 'value': s.value},
          ),
    ];
  }
}
