/// SyncEngine 逻辑测试（用内存 DavClient，真实协议栈留给 P1-8）
///
/// 覆盖：
///   1. 空远端首推 v1；无变更再同步不推新版本；
///   2. 第二台设备拉取并落地，且不重复推送；
///   3. 增量：A 改 → 推 v2 → B 拿到；
///   4. 删除：A 删 → 墓碑 → B 同步后删除；
///   5. 裁剪：超过 7 份只留最近 7 份。

import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync/sync.dart';

/// 内存 WebDAV：按路径存字节，目录由前缀隐式表达
class InMemoryDav implements DavClient {
  /// 路径 → 内容
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
        path: '$prefix$seg',
        isDirectory: isDir,
        size: isDir ? null : entry.value.length,
      ));
    }
    return out;
  }

  @override
  Future<List<int>?> read(String path) async => files[path];

  @override
  Future<void> write(String path, List<int> bytes, {String? ifMatch}) async {
    files[path] = List<int>.from(bytes);
  }

  @override
  Future<void> delete(String path) async {
    files.removeWhere(
      (k, _) => k == path || k.startsWith('$path/'),
    );
  }

  @override
  Future<void> mkdir(String path) async {}
}

/// 造一套「一台设备」的依赖
({SyncEngine engine, InMemoryDatabaseProvider db, MemorySyncStateStore state})
    device(String id, InMemoryDav dav, {AssetStore? assets}) {
  final db = InMemoryDatabaseProvider();
  final state = MemorySyncStateStore();
  return (
    engine: SyncEngine(
      dav: dav,
      db: db,
      state: state,
      deviceId: id,
      deviceName: id,
      assetStore: assets,
    ),
    db: db,
    state: state,
  );
}

/// 固定时间（避免真实时钟影响断言）
DateTime t(int seconds) => DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

void main() {
  test('空远端首推 v1；无变更再同步不推新版本', () async {
    final dav = InMemoryDav();
    final a = device('A', dav);
    await a.db.favoritesDao.addFavorite('s:1', 1000);

    final r1 = await a.engine.sync(now: t(10));
    expect(r1.success, isTrue);
    expect(r1.pushed, isTrue);
    expect(r1.toVersion, 1);
    final r2 = await a.engine.sync(now: t(20));
    expect(r2.success, isTrue);
    expect(r2.pushed, isFalse);
    expect(r2.toVersion, 1);
  });

  test('第二台设备拉取并落地，且不重复推送', () async {
    final dav = InMemoryDav();
    final a = device('A', dav);
    await a.db.favoritesDao.addFavorite('s:1', 1000);
    await a.engine.sync(now: t(10));

    final b = device('B', dav);
    final r = await b.engine.sync(now: t(20));
    expect(r.success, isTrue);
    expect(r.pushed, isFalse);
    expect(await b.db.favoritesDao.isFavorite('s:1'), isTrue);
  });

  test('增量：A 改 → 推 v2 → B 拿到', () async {
    final dav = InMemoryDav();
    final a = device('A', dav);
    await a.db.favoritesDao.addFavorite('s:1', 1000);
    await a.engine.sync(now: t(10));

    final b = device('B', dav);
    await b.engine.sync(now: t(20));

    await a.db.favoritesDao.addFavorite('s:2', 2000);
    final r = await a.engine.sync(now: t(30));
    expect(r.pushed, isTrue);
    expect(r.toVersion, 2);

    await b.engine.sync(now: t(40));
    expect(await b.db.favoritesDao.isFavorite('s:2'), isTrue);
  });

  test('删除：A 删 → 墓碑 → B 同步后删除', () async {
    final dav = InMemoryDav();
    final a = device('A', dav);
    await a.db.favoritesDao.addFavorite('s:1', 1000);
    await a.engine.sync(now: t(10));

    final b = device('B', dav);
    await b.engine.sync(now: t(20));
    expect(await b.db.favoritesDao.isFavorite('s:1'), isTrue);

    await a.db.favoritesDao.removeFavorite('s:1');
    final r = await a.engine.sync(now: t(30));
    expect(r.pushed, isTrue);

    await b.engine.sync(now: t(40));
    expect(await b.db.favoritesDao.isFavorite('s:1'), isFalse);
  });

  test('裁剪：推送超过 7 次只保留最近 7 份', () async {
    final dav = InMemoryDav();
    final a = device('A', dav);
    await a.db.favoritesDao.addFavorite('s:0', 100);
    await a.engine.sync(now: t(10));

    for (var i = 1; i <= 8; i++) {
      await a.db.favoritesDao.addFavorite('s:$i', 100 + i);
      await a.engine.sync(now: t(10 + i));
    }

    final versions = await a.engine.listVersions();
    expect(versions.length, 7);
    expect(versions.last, 9); // 首推 v1 + 8 次增量 = v9
  });

  test('resetRemote：清空云端与本地同步状态', () async {
    final dav = InMemoryDav();
    final a = device('A', dav);
    await a.db.favoritesDao.addFavorite('s:1', 1000);
    await a.engine.sync(now: t(10));

    await a.engine.resetRemote();
    expect(await a.engine.listVersions(), isEmpty);
    expect(await a.state.readKnownVersion(), isNull);
    expect(await a.state.readBaseline(), isNull);
  });

  test('资产：A 写→B 拿到；B 改→A 拿到；删除经墓碑传播', () async {
    final dav = InMemoryDav();
    final storeA = MemoryAssetStore();
    final storeB = MemoryAssetStore();
    final a = device('A', dav, assets: storeA);
    final b = device('B', dav, assets: storeB);

    await storeA.write(<AssetFile>[
      AssetFile(
        path: 'subscriptions/index.json',
        bytes: utf8.encode('v1'),
        mtime: 100,
      ),
    ]);
    await a.engine.sync(now: t(10));
    await b.engine.sync(now: t(20));
    expect(utf8.decode((await storeB.readAll()).single.bytes), 'v1');

    // B 修改同一文件（mtime 更新）→ 推 v2 → A 拿到
    await storeB.write(<AssetFile>[
      AssetFile(
        path: 'subscriptions/index.json',
        bytes: utf8.encode('v2'),
        mtime: 200,
      ),
    ]);
    await b.engine.sync(now: t(30));
    await a.engine.sync(now: t(40));
    expect(utf8.decode((await storeA.readAll()).single.bytes), 'v2');

    // A 新增一个文件并同步，再由 A 删除它（走墓碑）
    await storeA.write(<AssetFile>[
      AssetFile(
        path: 'subscriptions/other.json',
        bytes: utf8.encode('x'),
        mtime: 300,
      ),
    ]);
    await a.engine.sync(now: t(50));
    await b.engine.sync(now: t(60));
    expect((await storeB.readAll()).length, 2);

    await storeA.delete(<String>['subscriptions/other.json']);
    await a.engine.sync(now: t(70));
    await b.engine.sync(now: t(80));
    expect(
      (await storeB.readAll()).map((f) => f.path),
      <String>['subscriptions/index.json'],
    );
  });

  test('手动与自动触发写进 latest 的 trigger', () async {
    final dav = InMemoryDav();
    final a = device('A', dav);
    await a.db.favoritesDao.addFavorite('s:1', 1000);
    await a.engine.sync(now: t(10), trigger: 'manual');
    final latest = LatestDoc.decode(utf8.decode(dav.files['/resonance-sync/latest.json']!));
    expect(latest.trigger, 'manual');
  });
}
