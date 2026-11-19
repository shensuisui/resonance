/// 同步引擎：拉取 → 合并 → 应用 → 推送 → 裁剪 → 基线
///
/// 云端只存「快照链 + latest 指针」，合并全部在本机完成
/// （docs/features/webdav-sync.md §6/§8）。
/// 资产（订阅库/规则/插件）随快照 zip 的 assets/ 一起走；未注入 [AssetStore]
/// 时完全不碰资产（P1 行为）。
library;

import 'dart:convert';

import 'package:core/core.dart';

import 'asset_store.dart';
import 'dav_client.dart';
import 'latest.dart';
import 'local_snapshot_applier.dart';
import 'local_snapshot_reader.dart';
import 'merge.dart';
import 'snapshot.dart';
import 'snapshot_codec.dart';
import 'sync_report.dart';
import 'sync_state_store.dart';

/// 同步引擎
class SyncEngine {
  /// WebDAV 客户端
  final DavClient dav;

  /// 数据库
  final DatabaseProvider db;

  /// 同步状态（基线 / 已知版本）
  final SyncStateStore state;

  /// 本机设备 id（UUID）
  final String deviceId;

  /// 本机设备名（展示用）
  final String deviceName;

  /// 远端根目录（默认 /resonance-sync）
  final String remoteRoot;

  /// 资产存储（null = 不同步资产）
  final AssetStore? assetStore;

  /// 保留的快照份数
  static const int keepVersions = 7;

  /// 墓碑保留天数
  static const int tombstoneDays = 90;

  bool _running = false;

  /// 构造
  SyncEngine({
    required this.dav,
    required this.db,
    required this.state,
    required this.deviceId,
    required this.deviceName,
    this.remoteRoot = '/resonance-sync',
    this.assetStore,
  });

  String get _root =>
      remoteRoot.endsWith('/') && remoteRoot.length > 1
          ? remoteRoot.substring(0, remoteRoot.length - 1)
          : remoteRoot;

  String get _latestPath => '$_root/latest.json';

  String _snapshotRel(int version) =>
      'snapshots/v${version.toString().padLeft(4, '0')}.tar.bz2';

  String _snapshotPath(int version) => '$_root/${_snapshotRel(version)}';

  /// 执行一次同步（自动：永远合并；无变更不产生新版本）
  Future<SyncReport> sync({DateTime? now, String trigger = 'auto'}) async {
    final at = now ?? DateTime.now();
    if (_running) {
      return SyncReport(at: at, error: '已有同步任务在进行');
    }
    _running = true;
    try {
      return await _loop(at, trigger);
    } on SyncException catch (e) {
      return SyncReport.failure(e.message, at: at);
    } on DavException catch (e) {
      return SyncReport.failure(e.message, at: at);
    } on Exception catch (e) {
      return SyncReport.failure('$e', at: at);
    } finally {
      _running = false;
    }
  }

  /// 同步主循环（带乐观并发重试）
  Future<SyncReport> _loop(DateTime at, String trigger) async {
    final baseline = await state.readBaseline();
    final reader = LocalSnapshotReader(db: db, deviceId: deviceId);
    final applier = LocalSnapshotApplier(db: db);

    for (var attempt = 0; attempt <= 2; attempt++) {
      final latest = await _readLatest();
      final remoteBundle = latest == null ? null : await _download(latest);
      final remote = remoteBundle?.snapshot;
      final remoteAssets = remoteBundle?.assets ?? const <String, List<int>>{};
      final nextVersion = (latest?.version ?? 0) + 1;

      final local = await reader.read(
        version: nextVersion,
        writer: deviceId,
        baseline: baseline,
        now: at,
      );
      final localAssets = await _readLocalAssets();
      final localMeta = <AssetEntry>[
        for (final f in localAssets)
          AssetEntry(path: f.path, sha256: f.sha256Hex, mtime: f.mtime),
      ];

      final tombstones = _mergeTombstones(
        remote?.tombstones ?? const <Tombstone>[],
        _localDeletions(baseline, local, localMeta, at),
        at,
      );

      final mergedEntities = <String, List<SyncRecord>>{};
      var conflicts = 0;
      for (final entity in SyncEntity.all) {
        final outcome = Merger.mergeEntity(
          entity: entity,
          local: local.recordsOf(entity),
          remote: remote?.recordsOf(entity) ?? const <SyncRecord>[],
          tombstones: tombstones,
          baseline: baseline?.recordsOf(entity),
        );
        mergedEntities[entity] = outcome.records;
        conflicts += outcome.conflicts;
      }

      final mergedMeta = assetStore == null
          ? const <AssetEntry>[]
          : Merger.mergeAssets(
              local: localMeta,
              remote: remote?.assets ?? const <AssetEntry>[],
              tombstones: tombstones,
            );
      final merged = SyncSnapshot(
        version: nextVersion,
        updatedAt: at.millisecondsSinceEpoch,
        writer: deviceId,
        entities: mergedEntities,
        tombstones: tombstones,
        assets: mergedMeta,
      );

      await applier.apply(merged);
      final mergedBytes = _assetBytes(
        mergedMeta,
        localAssets: localAssets,
        remoteAssets: remoteAssets,
      );
      await _applyAssets(mergedMeta, mergedBytes, tombstones);

      // 无变更：不产生新版本
      final sameAsRemote = remote != null &&
          SnapshotCodec.contentHash(merged) ==
              SnapshotCodec.contentHash(remote);
      if (sameAsRemote) {
        await state.writeBaseline(merged);
        await state.writeKnownVersion(latest!.version);
        return SyncReport(
          pulled: merged.recordCount,
          fromVersion: latest.version,
          toVersion: latest.version,
          conflicts: conflicts,
          at: at,
        );
      }

      // 推送前再确认没被其它设备抢先（否则重下重合）
      final check = await _readLatest();
      if ((check?.version ?? 0) != (latest?.version ?? 0)) {
        continue;
      }

      final bytes = SnapshotCodec.encode(
        SnapshotBundle(snapshot: merged, assets: mergedBytes),
      );
      final sha = SnapshotCodec.sha256Hex(bytes);
      await dav.mkdir('$_root/snapshots');
      await dav.write(_snapshotPath(nextVersion), bytes);
      final doc = LatestDoc(
        version: nextVersion,
        file: _snapshotRel(nextVersion),
        sha256: sha,
        updatedAt: at.millisecondsSinceEpoch,
        writer: deviceId,
        trigger: trigger,
        devices: _devicesWith(check, at),
      );
      await dav.write(_latestPath, utf8.encode(doc.encode()));
      await _pruneSnapshots();
      await state.writeBaseline(merged);
      await state.writeKnownVersion(nextVersion);

      return SyncReport(
        pulled: merged.recordCount,
        pushed: true,
        fromVersion: latest?.version,
        toVersion: nextVersion,
        conflicts: conflicts,
        at: at,
      );
    }
    throw const SyncException('并发冲突：重试后仍被其它设备抢先');
  }

  /// 读本机资产（未注入资产存储时为空）
  Future<List<AssetFile>> _readLocalAssets() async {
    final store = assetStore;
    if (store == null) return const <AssetFile>[];
    return store.readAll();
  }

  /// 为合并后的清单挑选字节：优先本机同 sha，否则用远端快照包里的
  Map<String, List<int>> _assetBytes(
    List<AssetEntry> meta, {
    required List<AssetFile> localAssets,
    required Map<String, List<int>> remoteAssets,
  }) {
    final localBy = <String, AssetFile>{
      for (final f in localAssets) f.path: f,
    };
    final out = <String, List<int>>{};
    for (final entry in meta) {
      final localFile = localBy[entry.path];
      if (localFile != null && localFile.sha256Hex == entry.sha256) {
        out[entry.path] = localFile.bytes;
        continue;
      }
      final remoteBytes = remoteAssets[entry.path];
      if (remoteBytes != null &&
          SnapshotCodec.sha256Hex(remoteBytes) == entry.sha256) {
        out[entry.path] = remoteBytes;
      }
    }
    return out;
  }

  /// 把合并后的资产写回本机：写入/覆盖，仅墓碑驱动的删除
  Future<void> _applyAssets(
    List<AssetEntry> meta,
    Map<String, List<int>> bytes,
    List<Tombstone> tombstones,
  ) async {
    final store = assetStore;
    if (store == null) return;
    final files = <AssetFile>[
      for (final entry in meta)
        if (bytes[entry.path] != null)
          AssetFile(
            path: entry.path,
            bytes: bytes[entry.path]!,
            mtime: entry.mtime,
          ),
    ];
    await store.write(files);

    final paths = <String>{for (final a in meta) a.path};
    final dead = <String>{
      for (final t in tombstones)
        if (t.entity == SyncEntity.assets && !paths.contains(t.key)) t.key,
    };
    if (dead.isNotEmpty) await store.delete(dead);
  }

  /// 读 latest.json（不存在返回 null）
  Future<LatestDoc?> _readLatest() async {
    final bytes = await dav.read(_latestPath);
    if (bytes == null) return null;
    return LatestDoc.decode(utf8.decode(bytes));
  }

  /// 下载并校验快照
  Future<SnapshotBundle> _download(LatestDoc latest) async {
    final bytes = await dav.read('$_root/${latest.file}');
    if (bytes == null) {
      throw SyncException('快照缺失：${latest.file}');
    }
    if (latest.sha256.isNotEmpty &&
        SnapshotCodec.sha256Hex(bytes) != latest.sha256) {
      throw SyncException('快照校验失败：${latest.file}');
    }
    return SnapshotCodec.decode(bytes);
  }

  /// 本机删除 → 墓碑（基线有、当前无）
  ///
  /// 刻意不覆盖 songs（索引缓存，不做删除传播）与 recent
  /// （上限 500 的滚动淘汰不是用户删除，避免墓碑噪音）。
  /// 资产：仅当本机资产非空时才推断删除——避免「目录未初始化/读不到」
  /// 被误判成「全删了」而把云端资产批删。
  List<Tombstone> _localDeletions(
    SyncSnapshot? baseline,
    SyncSnapshot local,
    List<AssetEntry> localAssets,
    DateTime at,
  ) {
    if (baseline == null) return const <Tombstone>[];
    final now = at.millisecondsSinceEpoch;
    final out = <Tombstone>[];
    const entities = <String>[
      SyncEntity.playlists,
      SyncEntity.favorites,
      SyncEntity.progress,
      SyncEntity.settings,
    ];
    for (final entity in entities) {
      final baseKeys = baseline.recordsOf(entity).map((r) => r.key).toSet();
      final localKeys = local.recordsOf(entity).map((r) => r.key).toSet();
      for (final key in baseKeys.difference(localKeys)) {
        out.add(Tombstone(
          entity: entity,
          key: key,
          deletedAt: now,
          deviceId: deviceId,
        ));
      }
    }
    if (assetStore != null && localAssets.isNotEmpty) {
      final basePaths = baseline.assets.map((a) => a.path).toSet();
      final localPaths = localAssets.map((a) => a.path).toSet();
      for (final path in basePaths.difference(localPaths)) {
        out.add(Tombstone(
          entity: SyncEntity.assets,
          key: path,
          deletedAt: now,
          deviceId: deviceId,
        ));
      }
    }
    return out;
  }

  /// 合并墓碑：同 key 取 deletedAt 最大者；超过保留期回收
  List<Tombstone> _mergeTombstones(
    List<Tombstone> remote,
    List<Tombstone> local,
    DateTime at,
  ) {
    final map = <String, Tombstone>{};
    for (final t in <Tombstone>[...remote, ...local]) {
      final k = '${t.entity}|${t.key}';
      final prev = map[k];
      if (prev == null || t.deletedAt > prev.deletedAt) map[k] = t;
    }
    final cutoff = at
        .subtract(const Duration(days: tombstoneDays))
        .millisecondsSinceEpoch;
    return <Tombstone>[
      for (final t in map.values)
        if (t.deletedAt >= cutoff) t,
    ];
  }

  /// 设备列表：沿用远端已知设备，刷新本机
  List<LatestDevice> _devicesWith(LatestDoc? prev, DateTime at) {
    final map = <String, LatestDevice>{
      for (final d in (prev?.devices ?? const <LatestDevice>[])) d.id: d,
    };
    map[deviceId] = LatestDevice(
      id: deviceId,
      name: deviceName,
      lastSeenAt: at.millisecondsSinceEpoch,
    );
    return map.values.toList();
  }

  /// 裁剪：只保留最近 [keepVersions] 份（best-effort）
  Future<void> _pruneSnapshots() async {
    List<DavEntry> entries;
    try {
      entries = await dav.list('$_root/snapshots');
    } on DavException {
      return;
    }
    final versions = <int>[];
    for (final e in entries) {
      final name = e.path.split('/').last;
      final m = RegExp(r'^v(\d+)\.tar\.bz2$').firstMatch(name);
      if (m != null) versions.add(int.parse(m.group(1)!));
    }
    versions.sort();
    final removeCount = versions.length - keepVersions;
    for (var i = 0; i < removeCount; i++) {
      try {
        await dav.delete(_snapshotPath(versions[i]));
      } on DavException {
        // 裁剪失败不影响同步成功，下次再清
      }
    }
  }

  /// 列出云端历史版本（升序）
  Future<List<int>> listVersions() async {
    List<DavEntry> entries;
    try {
      entries = await dav.list('$_root/snapshots');
    } on DavException {
      return const <int>[];
    }
    final versions = <int>[];
    for (final e in entries) {
      final name = e.path.split('/').last;
      final m = RegExp(r'^v(\d+)\.tar\.bz2$').firstMatch(name);
      if (m != null) versions.add(int.parse(m.group(1)!));
    }
    versions.sort();
    return versions;
  }

  /// 回滚到指定历史版本（覆盖本机；不推送）
  Future<SyncReport> restoreVersion(int version, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final bytes = await dav.read(_snapshotPath(version));
    if (bytes == null) {
      return SyncReport.failure('版本 v$version 不存在', at: at);
    }
    final bundle = SnapshotCodec.decode(bytes);
    final snapshot = bundle.snapshot;
    await LocalSnapshotApplier(db: db).apply(snapshot);
    if (assetStore != null) {
      final meta = snapshot.assets;
      final files = <AssetFile>[
        for (final entry in meta)
          if (bundle.assets[entry.path] != null)
            AssetFile(
              path: entry.path,
              bytes: bundle.assets[entry.path]!,
              mtime: entry.mtime,
            ),
      ];
      await assetStore!.write(files);
    }
    await state.writeBaseline(snapshot);
    await state.writeKnownVersion(version);
    return SyncReport(
      pulled: snapshot.recordCount,
      fromVersion: version,
      toVersion: version,
      at: at,
    );
  }

  /// 重置同步：清空云端目录与本地状态（下一次同步会重新全量推）
  Future<void> resetRemote() async {
    try {
      await dav.delete(_root);
    } on DavException {
      // 目录不存在：忽略
    }
    await state.writeBaseline(null);
    await state.writeKnownVersion(null);
  }
}