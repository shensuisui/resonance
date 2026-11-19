/// 快照 → 本地：把合并后的快照写回 DB
///
/// 与 [LocalSnapshotReader] 对称。关键规则（docs/features/webdav-sync.md）：
///   * songs：只补缺 + 更新元数据，**不动 play_url / lyric_url / local_path**
///     （地址类字段由本机按来源重新解析，避免把过期 URL 写进来）；
///   * playlists：按 name 命中本机就沿用本机 id，并把 progress.queueId 一起重映射
///     （否则跨设备的播放进度会对不上）；
///   * favorites / recent / progress / settings：以合并结果为全集，
///     本机多出来的（= 已被合并删除）同步删除；settings 只动白名单键。
library;

import 'package:core/core.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'snapshot.dart';
import 'sync_settings_keys.dart';

/// 把快照写回 DB
class LocalSnapshotApplier {
  /// 数据库提供者
  final DatabaseProvider db;

  /// 构造
  const LocalSnapshotApplier({required this.db});

  /// 应用一份合并后的快照
  Future<void> apply(SyncSnapshot snapshot) async {
    // 歌单先写：progress 的 queueId 需要按 id 映射改写
    final playlistIdMap = await _applyPlaylists(snapshot);
    await _applySongs(snapshot);
    await _applyFavorites(snapshot);
    await _applyRecent(snapshot);
    await _applyProgress(snapshot, playlistIdMap);
    await _applySettings(snapshot);
  }

  /// 稳定派生歌单 id（远端记录未带 id 时用）
  String _stableId(String name) =>
      'pl_' + sha256.convert(utf8.encode(name)).toString().substring(0, 16);

  /// 写回歌单；返回 远端 id → 本机 id 的映射
  Future<Map<String, String>> _applyPlaylists(SyncSnapshot snapshot) async {
    final existing = await db.playlistDao.getAllPlaylists();
    final byName = <String, Playlist>{for (final p in existing) p.name: p};
    final idMap = <String, String>{};

    for (final rec in snapshot.recordsOf(SyncEntity.playlists)) {
      final name = rec.key;
      final data = rec.data;
      final remoteId = (data['id'] as String?) ?? '';
      final local = byName[name];
      final id = local?.id ??
          (remoteId.isNotEmpty ? remoteId : _stableId(name));
      if (remoteId.isNotEmpty && remoteId != id) idMap[remoteId] = id;

      final songKeys =
          ((data['songKeys'] as List?) ?? const <Object?>[]).cast<String>();
      final snapJson = ((data['snapshots'] as Map?) ?? const <String, Object?>{})
          .cast<String, Object?>();
      final snapshots = <String, Song>{
        for (final e in snapJson.entries) e.key: _songFromSnapshot(e.value),
      };
      final modified =
          DateTime.fromMillisecondsSinceEpoch(rec.updatedAt);

      final playlist = Playlist(
        id: id,
        name: name,
        songKeys: songKeys,
        songSnapshots: snapshots,
        sourceId: local?.sourceId,
        sourcePlaylistId: local?.sourcePlaylistId,
        coverUrl: local?.coverUrl,
        createdTime: local?.createdTime ?? modified,
        modifiedTime: modified,
      );
      if (local == null) {
        await db.playlistDao.insertPlaylist(playlist);
      } else {
        await db.playlistDao.updatePlaylist(playlist);
      }
    }
    return idMap;
  }

  /// 从歌单快照里的 {key: {title,...}} 还原 Song（仅展示用元数据）
  Song _songFromSnapshot(Object? raw) {
    final map = (raw as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    // 这里的 Song 只是快照载体，id/sourceId 由外层 key 决定；占位即可
    return Song(
      id: '',
      sourceId: '',
      title: (map['title'] as String?) ?? '',
      artist: (map['artist'] as String?) ?? '',
      coverUrl: map['coverUrl'] as String?,
      duration: (map['duration'] as num?)?.toInt(),
    );
  }

  /// 写回歌曲：只补缺 + 更新元数据，不动地址类字段
  Future<void> _applySongs(SyncSnapshot snapshot) async {
    for (final rec in snapshot.recordsOf(SyncEntity.songs)) {
      final d = rec.data;
      final id = (d['id'] as String?) ?? '';
      final sourceId = (d['sourceId'] as String?) ?? '';
      if (id.isEmpty || sourceId.isEmpty) continue;

      final existing = await db.songDao.getSong(id, sourceId);
      if (existing == null) {
        // 新曲：只落元数据；playUrl/lyricUrl 由本机按来源重新解析
        await db.songDao.insertSong(Song(
          id: id,
          sourceId: sourceId,
          title: (d['title'] as String?) ?? '',
          artist: (d['artist'] as String?) ?? '',
          album: d['album'] as String?,
          coverUrl: d['coverUrl'] as String?,
          duration: (d['duration'] as num?)?.toInt(),
          extra: (d['extra'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{},
        ));
      } else {
        // 已有曲：只更新元数据，保留本机的 playUrl/lyricUrl/localPath/lyric
        await db.songDao.updateSong(existing.copyWith(
          title: (d['title'] as String?) ?? existing.title,
          artist: (d['artist'] as String?) ?? existing.artist,
          album: d['album'] as String?,
          coverUrl: d['coverUrl'] as String?,
          duration: (d['duration'] as num?)?.toInt(),
        ));
      }
    }
  }

  /// 写回收藏（合并结果是全集）
  Future<void> _applyFavorites(SyncSnapshot snapshot) async {
    final records = snapshot.recordsOf(SyncEntity.favorites);
    final desired = <String>{for (final r in records) r.key};

    for (final rec in records) {
      final d = rec.data;
      await db.favoritesDao.addFavorite(
        rec.key,
        (d['time'] as num?)?.toInt() ?? rec.updatedAt,
        title: d['title'] as String?,
        artist: d['artist'] as String?,
        coverUrl: d['coverUrl'] as String?,
      );
    }
    for (final key in await db.favoritesDao.getAllFavoriteKeys()) {
      if (!desired.contains(key)) {
        await db.favoritesDao.removeFavorite(key);
      }
    }
  }

  /// 写回最近播放（合并后截断到 500）
  Future<void> _applyRecent(SyncSnapshot snapshot) async {
    final records = snapshot.recordsOf(SyncEntity.recent);
    final desired = <String>{for (final r in records) r.key};

    for (final rec in records) {
      final d = rec.data;
      await db.recentPlaysDao.insertOrUpdateRecentPlay(
        rec.key,
        (d['playedAt'] as num?)?.toInt() ?? rec.updatedAt,
        title: d['title'] as String?,
        artist: d['artist'] as String?,
        coverUrl: d['coverUrl'] as String?,
      );
    }
    for (final key in await db.recentPlaysDao.getRecentPlayKeys(limit: 500)) {
      if (!desired.contains(key)) {
        await db.recentPlaysDao.deleteRecentPlay(key);
      }
    }
    await db.recentPlaysDao.cleanOldest(500);
  }

  /// 写回播放进度（歌单队列的 id 按映射改写）
  Future<void> _applyProgress(
    SyncSnapshot snapshot,
    Map<String, String> playlistIdMap,
  ) async {
    final records = snapshot.recordsOf(SyncEntity.progress);
    String mapId(String kind, String id) =>
        kind == 'playlist' ? (playlistIdMap[id] ?? id) : id;

    final desired = <String>{};
    for (final rec in records) {
      final d = rec.data;
      final kind = (d['queueKind'] as String?) ?? '';
      final rawId = (d['queueId'] as String?) ?? '';
      final id = mapId(kind, rawId);
      desired.add('$kind|$id');
      await db.playProgressDao.upsert(PlayProgress(
        queueKind: kind,
        queueId: id,
        songKey: (d['songKey'] as String?) ?? '',
        positionMs: (d['positionMs'] as num?)?.toInt() ?? 0,
        updatedAt: (d['updatedAt'] as num?)?.toInt() ?? rec.updatedAt,
      ));
    }
    for (final p in await db.playProgressDao.getAll()) {
      final key = '${p.queueKind}|${p.queueId}';
      if (!desired.contains(key)) {
        await db.playProgressDao.delete(p.queueKind, p.queueId);
      }
    }
  }

  /// 写回设置（只动白名单键）
  Future<void> _applySettings(SyncSnapshot snapshot) async {
    final records = snapshot.recordsOf(SyncEntity.settings);
    final desired = <String>{for (final r in records) r.key};

    for (final rec in records) {
      final value = (rec.data['value'] as String?) ?? '';
      await db.settingsDao.set(rec.key, value);
    }
    for (final entry in await db.settingsDao.getAllEntries()) {
      if (SyncSettingsKeys.isSyncable(entry.key) &&
          !desired.contains(entry.key)) {
        await db.settingsDao.delete(entry.key);
      }
    }
  }
}
