/// SyncAutoRunner 测试（真实计时器，不 mock 平台）
///
/// 覆盖：启动拉取、变更防抖合并、仅 Wi-Fi 跳过、关闭时不触发、定时触发与 dispose 停止。

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonance_app/sync/sync_auto_runner.dart';

/// 假宿主
class FakeHost implements AutoSyncHost {
  final changesCtl = StreamController<DbChange>.broadcast();
  final configCtl = StreamController<void>.broadcast();
  bool enabledFlag = true;
  bool wifiOnlyFlag = false;
  bool startupFlag = true;
  int debounceMs = 30;
  int intervalMs = 0;
  int syncCount = 0;

  @override
  Stream<DbChange>? get changes => changesCtl.stream;
  @override
  Stream<void> get configChanges => configCtl.stream;
  @override
  Future<bool> get enabled async => enabledFlag;
  @override
  Future<bool> get wifiOnly async => wifiOnlyFlag;
  @override
  Future<bool> get startupPull async => startupFlag;
  @override
  Future<int> get debounceMillis async => debounceMs;
  @override
  Future<int> get intervalMillis async => intervalMs;
  @override
  Future<void> syncAuto() async => syncCount++;

  Future<void> close() async {
    await changesCtl.close();
    await configCtl.close();
  }
}

/// 等一段真实时间
Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  test('启动拉取：开启且 startupPull 时立即同步一次', () async {
    final host = FakeHost();
    final runner = SyncAutoRunner(host: host);
    await runner.start();
    await wait(30);
    expect(host.syncCount, 1);
    await runner.dispose();
    await host.close();
  });

  test('变更防抖：连续 3 次变更只触发 1 次', () async {
    final host = FakeHost();
    final runner = SyncAutoRunner(host: host);
    await runner.start();
    await wait(30); // 启动拉取 1 次
    host.changesCtl.add(DbChange(DbEntity.favorites, DateTime.now()));
    host.changesCtl.add(DbChange(DbEntity.favorites, DateTime.now()));
    host.changesCtl.add(DbChange(DbEntity.favorites, DateTime.now()));
    await wait(120);
    expect(host.syncCount, 2); // 启动 1 + 防抖 1
    await runner.dispose();
    await host.close();
  });

  test('仅 Wi-Fi：不在 Wi-Fi 时跳过自动同步', () async {
    final host = FakeHost()..wifiOnlyFlag = true;
    final runner = SyncAutoRunner(host: host, isOnWifi: () async => false);
    await runner.start();
    await wait(30);
    expect(host.syncCount, 0); // 启动拉取被 Wi-Fi 门禁挡住
    await runner.dispose();
    await host.close();
  });

  test('关闭开关：不启动拉取也不响应变更', () async {
    final host = FakeHost()..enabledFlag = false;
    final runner = SyncAutoRunner(host: host);
    await runner.start();
    host.changesCtl.add(DbChange(DbEntity.songs, DateTime.now()));
    await wait(80);
    expect(host.syncCount, 0);
    await runner.dispose();
    await host.close();
  });

  test('定时同步：间隔到点触发，dispose 后停止', () async {
    final host = FakeHost()
      ..startupFlag = false
      ..intervalMs = 60;
    final runner = SyncAutoRunner(host: host);
    await runner.start();
    await wait(200);
    final atLeast = host.syncCount;
    expect(atLeast, greaterThanOrEqualTo(2));
    await runner.dispose();
    final snapshot = host.syncCount;
    await wait(150);
    expect(host.syncCount, snapshot); // 已停止
    await host.close();
  });
}
