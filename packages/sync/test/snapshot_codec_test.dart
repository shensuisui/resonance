/// 快照编解码测试
///
/// 覆盖：
///   1. tar+bzip2 往返：记录/墓碑/资产字节原样还原；
///   2. sha256 长度与稳定性；
///   3. 高 schema 拒绝（要求升级 App）；
///   4. 损坏字节包抛 SnapshotException；
///   5. latest.json 往返与设备列表合并。
///
/// 不依赖网络与真实 WebDAV：只验证编解码与格式契约。

import 'package:flutter_test/flutter_test.dart';
import 'package:sync/sync.dart';

/// 构造一份含 2 个实体 + 1 条墓碑 + 2 个资产文件的测试快照
SnapshotBundle _bundle() {
  final now = DateTime.now().millisecondsSinceEpoch;
  return SnapshotBundle(
    snapshot: SyncSnapshot(
      version: 7,
      updatedAt: now,
      writer: 'device-a',
      entities: <String, List<SyncRecord>>{
        SyncEntity.favorites: <SyncRecord>[
          SyncRecord(
            key: 'gequbao:1',
            updatedAt: now,
            deviceId: 'device-a',
            data: <String, Object?>{'songKey': 'gequbao:1', 'title': '素颜'},
          ),
        ],
        SyncEntity.settings: <SyncRecord>[
          SyncRecord(
            key: 'theme_mode',
            updatedAt: now - 1000,
            deviceId: 'device-b',
            data: <String, Object?>{'key': 'theme_mode', 'value': 'dark'},
          ),
        ],
      },
      tombstones: <Tombstone>[
        Tombstone(
          entity: SyncEntity.recent,
          key: 'gequbao:2',
          deletedAt: now,
          deviceId: 'device-a',
        ),
      ],
    ),
    assets: <String, List<int>>{
      'subscriptions/index.json': <int>[123, 34, 91, 93, 125],
      'subscriptions/abc/manifest.json': <int>[123, 125],
    },
  );
}

void main() {
  test('tar+bzip2 往返：记录/墓碑/资产字节原样还原', () {
    final bundle = _bundle();
    final encoded = SnapshotCodec.encode(bundle);
    expect(encoded, isNotEmpty);

    final decoded = SnapshotCodec.decode(encoded);
    expect(decoded.snapshot.version, 7);
    expect(decoded.snapshot.writer, 'device-a');
    expect(decoded.snapshot.recordsOf(SyncEntity.favorites).length, 1);
    expect(
      decoded.snapshot.recordsOf(SyncEntity.favorites).first.data['title'],
      '素颜',
    );
    expect(decoded.snapshot.tombstones.single.key, 'gequbao:2');
    expect(
      decoded.assets['subscriptions/index.json'],
      bundle.assets['subscriptions/index.json'],
    );
    expect(
      decoded.assets['subscriptions/abc/manifest.json'],
      bundle.assets['subscriptions/abc/manifest.json'],
    );
  });

  test('sha256：64 位十六进制且对同一字节稳定', () {
    final bytes = SnapshotCodec.encode(_bundle());
    final a = SnapshotCodec.sha256Hex(bytes);
    final b = SnapshotCodec.sha256Hex(bytes);
    expect(a.length, 64);
    expect(a, b);
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(a), isTrue);
  });

  test('快照版本高于当前：拒绝并提示升级', () {
    final json = <String, Object?>{
      'format': SnapshotCodec.magic,
      'schema': SnapshotCodec.schema + 1,
      'version': 1,
      'updatedAt': 0,
      'writer': 'x',
      'entities': <String, Object?>{},
      'tombstones': <Object?>[],
    };
    expect(
      () => SnapshotCodec.fromJson(json),
      throwsA(isA<SnapshotException>()),
    );
  });

  test('损坏字节包：抛 SnapshotException 而不是崩溃', () {
    expect(
      () => SnapshotCodec.decode(<int>[1, 2, 3, 4, 5]),
      throwsA(isA<SnapshotException>()),
    );
  });

  test('latest.json 往返 + 设备列表按 id 合并取较新', () {
    final doc = LatestDoc(
      version: 7,
      file: 'snapshots/v0007.tar.bz2',
      sha256: 'a' * 64,
      updatedAt: 100,
      writer: 'device-a',
      devices: const <LatestDevice>[
        LatestDevice(id: 'a', name: 'Pixel', lastSeenAt: 100),
      ],
    );
    final decoded = LatestDoc.decode(doc.encode());
    expect(decoded.version, 7);
    expect(decoded.file, 'snapshots/v0007.tar.bz2');
    expect(decoded.devices.single.name, 'Pixel');

    final merged = decoded.withDevice(
      const LatestDevice(id: 'a', name: 'Pixel 7', lastSeenAt: 200),
    );
    expect(merged.devices.single.name, 'Pixel 7');
    expect(merged.devices.single.lastSeenAt, 200);
  });

  test('latest 魔数不符：抛 FormatException', () {
    expect(
      () => LatestDoc.decode('{"format":"other"}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('资产清单元数据随快照往返', () {
    final bundle = SnapshotBundle(
      snapshot: SyncSnapshot(
        version: 1,
        updatedAt: 1,
        writer: 'w',
        assets: const <AssetEntry>[
          AssetEntry(path: 'a.json', sha256: 'abc', mtime: 123),
        ],
      ),
      assets: <String, List<int>>{'a.json': <int>[1, 2, 3]},
    );
    final decoded = SnapshotCodec.decode(SnapshotCodec.encode(bundle));
    expect(decoded.snapshot.assets.single.path, 'a.json');
    expect(decoded.snapshot.assets.single.sha256, 'abc');
    expect(decoded.snapshot.assets.single.mtime, 123);
    expect(decoded.assets['a.json'], <int>[1, 2, 3]);
  });
}