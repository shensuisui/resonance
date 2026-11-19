/// SyncStatusCache 与连接名映射测试（纯逻辑，不 mock 平台）
///
/// 覆盖：同步结果写读往返（含冲突明细）、清空、remoteLabelOf 的命名规则。

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonance_app/sync/shell_sync_service.dart';
import 'package:sync/sync.dart';

void main() {
  test('remoteLabelOf：坚果云 / Nextcloud / 域名', () {
    expect(remoteLabelOf('https://dav.jianguoyun.com/dav'), '坚果云');
    expect(remoteLabelOf('https://cloud.example.com/nextcloud'), 'Nextcloud');
    expect(remoteLabelOf('https://dav.example.com/dav'), 'dav.example.com');
    expect(remoteLabelOf(''), '');
  });

  test('状态缓存：写读往返（含冲突明细），清空后为空', () async {
    final dao = InMemorySettingsDao();
    final cache = SyncStatusCache(dao);

    final report = SyncReport(
      pulled: 10,
      pushed: true,
      fromVersion: 41,
      toVersion: 42,
      conflicts: 1,
      conflictList: <MergeConflict>[
        const MergeConflict(
          entity: 'playlists',
          key: '夜行',
          localUpdatedAt: 1000,
          remoteUpdatedAt: 2000,
        ),
      ],
      at: DateTime.now(),
    );
    await cache.writeReport(report);

    final read = await cache.read();
    expect(read.to, 42);
    expect(read.from, 41);
    expect(read.status, 'conflict');
    expect(read.conflicts.single.entity, 'playlists');
    expect(read.conflicts.single.key, '夜行');

    await cache.clearResult();
    final cleared = await cache.read();
    expect(cleared.to, isNull);
    expect(cleared.status, isNull);
    expect(cleared.conflicts, isEmpty);
  });
}
