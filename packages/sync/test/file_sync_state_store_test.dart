/// 文件版同步状态存储测试
///
/// 覆盖：
///   1. 基线往返（含资产清单）与清空；
///   2. 已知版本读写与清空；
///   3. 基线损坏时按「没有基线」处理（安全侧，不推断删除）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync/sync.dart';

/// 构造一份带资产清单的快照
SyncSnapshot _snapshot(int version) => SyncSnapshot(
      version: version,
      updatedAt: 1000,
      writer: 'w',
      entities: <String, List<SyncRecord>>{
        SyncEntity.favorites: <SyncRecord>[
          SyncRecord(
            key: 's:1',
            updatedAt: 1000,
            deviceId: 'w',
            data: <String, Object?>{'songKey': 's:1'},
          ),
        ],
      },
      assets: const <AssetEntry>[
        AssetEntry(path: 'subscriptions/index.json', sha256: 'abc', mtime: 9),
      ],
    );

void main() {
  late Directory tmp;
  late FileSyncStateStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sync_state_test');
    store = FileSyncStateStore(tmp.path);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('基线往返（含资产清单），清空后为 null', () async {
    expect(await store.readBaseline(), isNull);
    await store.writeBaseline(_snapshot(3));

    final read = await store.readBaseline();
    expect(read, isNotNull);
    expect(read!.version, 3);
    expect(read.recordsOf(SyncEntity.favorites).single.key, 's:1');
    expect(read.assets.single.path, 'subscriptions/index.json');

    await store.writeBaseline(null);
    expect(await store.readBaseline(), isNull);
  });

  test('已知版本读写与清空', () async {
    expect(await store.readKnownVersion(), isNull);
    await store.writeKnownVersion(7);
    expect(await store.readKnownVersion(), 7);
    await store.writeKnownVersion(null);
    expect(await store.readKnownVersion(), isNull);
  });

  test('基线损坏：按没有基线处理（不抛异常）', () async {
    await File('${tmp.path}/baseline.tar.bz2').writeAsBytes(<int>[1, 2, 3]);
    expect(await store.readBaseline(), isNull);
  });
}
