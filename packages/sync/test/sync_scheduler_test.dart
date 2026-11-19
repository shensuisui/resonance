/// SyncScheduler 测试
///
/// 覆盖：
///   1. 连续变更只触发一次（防抖）；
///   2. flush 立即同步并取消待执行防抖；
///   3. dispose 后不再触发。

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync/sync.dart';

/// 等一段时间（真实计时器，验证防抖行为）
Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  test('连续变更只触发一次（防抖）', () async {
    final bus = StreamController<DbChange>.broadcast();
    var calls = 0;
    final scheduler = SyncScheduler(
      changes: bus.stream,
      debounce: const Duration(milliseconds: 40),
      onSync: () async {
        calls++;
        return SyncReport(at: DateTime.now());
      },
    )..start();

    bus.add(DbChange(DbEntity.favorites, DateTime.now()));
    bus.add(DbChange(DbEntity.favorites, DateTime.now()));
    bus.add(DbChange(DbEntity.favorites, DateTime.now()));
    await wait(120);

    expect(calls, 1);
    await scheduler.dispose();
    await bus.close();
  });

  test('flush 立即同步并取消待执行防抖', () async {
    final bus = StreamController<DbChange>.broadcast();
    var calls = 0;
    final scheduler = SyncScheduler(
      changes: bus.stream,
      debounce: const Duration(seconds: 5),
      onSync: () async {
        calls++;
        return SyncReport(at: DateTime.now());
      },
    )..start();

    scheduler.schedule();
    await scheduler.flush();
    expect(calls, 1);

    // 原防抖已被取消，等一段也不会再触发
    await wait(100);
    expect(calls, 1);

    await scheduler.dispose();
    await bus.close();
  });

  test('dispose 后不再触发', () async {
    final bus = StreamController<DbChange>.broadcast();
    var calls = 0;
    final scheduler = SyncScheduler(
      changes: bus.stream,
      debounce: const Duration(milliseconds: 30),
      onSync: () async {
        calls++;
        return SyncReport(at: DateTime.now());
      },
    )..start();

    await scheduler.dispose();
    scheduler.schedule();
    bus.add(DbChange(DbEntity.songs, DateTime.now()));
    await wait(100);
    expect(calls, 0);

    await bus.close();
  });
}