/// 合并纯函数测试
///
/// 覆盖：
///   1. 集合并集 + 取较新者；
///   2. updatedAt 相同按 deviceId 兜底（确定性）；
///   3. 墓碑删除 / 记录更新可「重新加入」；
///   4. 冲突只在「双方都改过且 data 不同」时计数（依赖基线）；
///   5. 歌单：曲目并集、顺序以较新者为主、独有曲目追加末尾。

import 'package:test/test.dart';
import 'package:portable/portable.dart';

/// 构造一条记录
SyncRecord _rec(
  String key,
  int updatedAt, {
  String deviceId = 'd',
  Map<String, Object?> data = const <String, Object?>{},
}) =>
    SyncRecord(
      key: key,
      updatedAt: updatedAt,
      deviceId: deviceId,
      data: data,
    );

void main() {
  test('并集 + 取较新者', () {
    final out = Merger.mergeEntity(
      entity: SyncEntity.favorites,
      local: <SyncRecord>[
        _rec('a', 10, data: <String, Object?>{'v': 1}),
        _rec('b', 20, data: <String, Object?>{'v': 2}),
      ],
      remote: <SyncRecord>[
        _rec('b', 30, data: <String, Object?>{'v': 3}),
        _rec('c', 40, data: <String, Object?>{'v': 4}),
      ],
    );
    final byKey = {for (final r in out.records) r.key: r};
    expect(byKey.keys.toSet(), <String>{'a', 'b', 'c'});
    expect(byKey['b']!.data['v'], 3);
    expect(byKey['b']!.updatedAt, 30);
    // 无基线时按「双方都有且 data 不同」计，b 记为 1 个冲突
    expect(out.conflictCount, 1);
  });

  test('updatedAt 相同：按 deviceId 兜底（大者胜，结果确定）', () {
    final out = Merger.mergeEntity(
      entity: SyncEntity.settings,
      local: <SyncRecord>[
        _rec('k', 10, deviceId: 'aaa', data: <String, Object?>{'v': 'local'}),
      ],
      remote: <SyncRecord>[
        _rec('k', 10, deviceId: 'zzz', data: <String, Object?>{'v': 'remote'}),
      ],
    );
    expect(out.records.single.data['v'], 'remote');
  });

  test('墓碑：删除时间更晚才删；记录更新过可重新加入', () {
    final out = Merger.mergeEntity(
      entity: SyncEntity.favorites,
      local: <SyncRecord>[
        _rec('gone', 10),
        _rec('back', 50),
      ],
      remote: const <SyncRecord>[],
      tombstones: const <Tombstone>[
        Tombstone(entity: SyncEntity.favorites, key: 'gone', deletedAt: 20, deviceId: 'r'),
        Tombstone(entity: SyncEntity.favorites, key: 'back', deletedAt: 30, deviceId: 'r'),
      ],
    );
    // gone: deletedAt(20) > updatedAt(10) → 删
    // back: deletedAt(30) < updatedAt(50) → 记录更新过，保留
    expect(out.records.map((r) => r.key), <String>['back']);
  });

  test('冲突：双方都改过且 data 不同才计数（相对基线）', () {
    const base = <String, Object?>{'v': 'base'};
    final local = <SyncRecord>[_rec('k', 20, data: <String, Object?>{'v': 'l'})];
    final remote = <SyncRecord>[_rec('k', 30, data: <String, Object?>{'v': 'r'})];

    // 双方都改过 → 冲突 1
    final both = Merger.mergeEntity(
      entity: SyncEntity.settings,
      local: local,
      remote: remote,
      baseline: <SyncRecord>[_rec('k', 10, data: base)],
    );
    expect(both.conflictCount, 1);

    // 远端与基线一致（没改），只有本地改过 → 不算冲突
    final onlyLocal = Merger.mergeEntity(
      entity: SyncEntity.settings,
      local: local,
      remote: remote,
      baseline: <SyncRecord>[_rec('k', 30, data: <String, Object?>{'v': 'r'})],
    );
    expect(onlyLocal.conflictCount, 0);
  });

  test('歌单：曲目并集、顺序以较新者为主、独有曲目追加末尾', () {
    final out = Merger.mergeEntity(
      entity: SyncEntity.playlists,
      local: <SyncRecord>[
        _rec('p1', 10, data: <String, Object?>{
          'songKeys': <String>['a', 'b'],
          'snapshots': <String, Object?>{
            'a': <String, Object?>{'title': '旧A'},
          },
        }),
      ],
      remote: <SyncRecord>[
        _rec('p1', 20, data: <String, Object?>{
          'songKeys': <String>['b', 'c'],
          'snapshots': <String, Object?>{
            'a': <String, Object?>{'title': '新A'},
            'c': <String, Object?>{'title': 'C'},
          },
        }),
      ],
    );
    final p = out.records.single;
    // 以 remote（较新）顺序为主：b,c；本地独有 a 追加末尾
    expect(p.data['songKeys'], <String>['b', 'c', 'a']);
    expect(p.updatedAt, 20);
    final snaps = (p.data['snapshots'] as Map).cast<String, Object?>();
    expect((snaps['a'] as Map)['title'], '新A'); // 较新者优先
  });

  test('资产合并：按 mtime 判胜、仅墓碑才删', () {
    final out = Merger.mergeAssets(
      local: const <AssetEntry>[
        AssetEntry(path: 'a.json', sha256: 'aaa', mtime: 10),
        AssetEntry(path: 'b.json', sha256: 'bbb', mtime: 20),
      ],
      remote: const <AssetEntry>[
        AssetEntry(path: 'a.json', sha256: 'zzz', mtime: 30),
        AssetEntry(path: 'c.json', sha256: 'ccc', mtime: 40),
      ],
      tombstones: const <Tombstone>[
        Tombstone(
          entity: SyncEntity.assets,
          key: 'b.json',
          deletedAt: 25,
          deviceId: 'r',
        ),
      ],
    );
    final byPath = <String, AssetEntry>{for (final a in out) a.path: a};
    expect(byPath.keys.toSet(), <String>{'a.json', 'c.json'});
    expect(byPath['a.json']!.sha256, 'zzz'); // 远端更新
    expect(byPath.containsKey('b.json'), isFalse); // 墓碑删除
  });

  test('资产合并：mtime 相同按 sha 决定（结果确定）', () {
    final out = Merger.mergeAssets(
      local: const <AssetEntry>[
        AssetEntry(path: 'a', sha256: 'aaa', mtime: 10),
      ],
      remote: const <AssetEntry>[
        AssetEntry(path: 'a', sha256: 'zzz', mtime: 10),
      ],
    );
    expect(out.single.sha256, 'zzz');
  });
}
