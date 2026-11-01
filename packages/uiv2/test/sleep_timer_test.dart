/// 睡眠定时器单元测试（lib/src/providers/providers.dart 的 SleepTimerNotifier）。
///
/// 测什么（fakeAsync 控制虚拟时钟，不真实等待）：
///   * start 后 state 每 1 秒递减；
///   * 倒计时到 0：state 归 null 并调用 player.pause()；
///   * cancel：停止倒计时、state 归 null，此后不再递减也不触发 pause；
///   * 重新 start 覆盖上一次倒计时（旧 Timer 被取消，按新时长重计）。
///
/// 模拟数据来源：InMemoryDatabaseProvider + 手写 _FakePlayer（显式实现
/// stateStream/positionStream/durationStream 为 const Stream.empty()，
/// pause 用可记录调用实现，其余成员 noSuchMethod）。
library;

import 'package:core/core.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/providers/providers.dart';

/// 手写假播放器：pause 可记录调用，其余接口显式实现或 noSuchMethod
class _FakePlayer implements Player {
  int pauseCalls = 0;

  @override
  Stream<PlayerState> get stateStream => const Stream.empty();
  @override
  Stream<int> get positionStream => const Stream.empty();
  @override
  Stream<int> get durationStream => const Stream.empty();
  @override
  Future<void> pause() async => pauseCalls++;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// 搭一个（数据库 + 播放器已 override 的）容器并返回
(ProviderContainer, _FakePlayer) _makeEnv() {
  final player = _FakePlayer();
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(InMemoryDatabaseProvider()),
    playerProvider.overrideWithValue(player),
  ]);
  return (container, player);
}

void main() {
  test('start 后每秒递减，到 0 调 player.pause 且 state 归 null', () {
    fakeAsync((async) {
      final (container, player) = _makeEnv();
      addTearDown(container.dispose);
      // 触发一次真实读取以完成容器装配（ThemeModeNotifier 等与本研究无关，
      // 但 SleepTimerNotifier 无持久化，读即建）
      container.read(themeModeProvider);
      async.flushMicrotasks();

      final notifier = container.read(sleepTimerProvider.notifier);
      expect(container.read(sleepTimerProvider), isNull);

      notifier.start(const Duration(seconds: 3));
      expect(container.read(sleepTimerProvider), const Duration(seconds: 3));

      async.elapse(const Duration(seconds: 1));
      expect(container.read(sleepTimerProvider), const Duration(seconds: 2));
      async.elapse(const Duration(seconds: 1));
      expect(container.read(sleepTimerProvider), const Duration(seconds: 1));
      // 尚未到 0：没触发 pause
      expect(player.pauseCalls, 0);

      async.elapse(const Duration(seconds: 1));
      // 到 0：state 归 null + 暂停播放
      expect(container.read(sleepTimerProvider), isNull);
      expect(player.pauseCalls, 1);

      // 到点后不再继续递减（Timer 已取消）
      async.elapse(const Duration(seconds: 5));
      expect(player.pauseCalls, 1);
    });
  });

  test('cancel 停止倒计时且不触发 pause', () {
    fakeAsync((async) {
      final (container, player) = _makeEnv();
      addTearDown(container.dispose);
      container.read(themeModeProvider);
      async.flushMicrotasks();

      final notifier = container.read(sleepTimerProvider.notifier);
      notifier.start(const Duration(seconds: 10));
      async.elapse(const Duration(seconds: 2));
      expect(container.read(sleepTimerProvider), const Duration(seconds: 8));

      notifier.cancel();
      expect(container.read(sleepTimerProvider), isNull);

      // 取消后时间继续走：不再递减、不触发 pause
      async.elapse(const Duration(seconds: 30));
      expect(container.read(sleepTimerProvider), isNull);
      expect(player.pauseCalls, 0);
    });
  });

  test('重新 start 覆盖已有倒计时', () {
    fakeAsync((async) {
      final (container, player) = _makeEnv();
      addTearDown(container.dispose);
      container.read(themeModeProvider);
      async.flushMicrotasks();

      final notifier = container.read(sleepTimerProvider.notifier);
      notifier.start(const Duration(seconds: 10));
      async.elapse(const Duration(seconds: 4));
      expect(container.read(sleepTimerProvider), const Duration(seconds: 6));

      // 重新设定：覆盖为 60 秒（旧 Timer 被取消）
      notifier.start(const Duration(minutes: 1));
      expect(container.read(sleepTimerProvider), const Duration(minutes: 1));

      // 如果旧 Timer 未被取消，再走 6 秒后旧定时器会把 state 清空/递减错乱
      async.elapse(const Duration(seconds: 6));
      expect(container.read(sleepTimerProvider), const Duration(seconds: 54));
      expect(player.pauseCalls, 0);

      // 走满新的 60 秒：到点暂停
      async.elapse(const Duration(seconds: 54));
      expect(container.read(sleepTimerProvider), isNull);
      expect(player.pauseCalls, 1);
    });
  });

  test('container dispose 取消内部 Timer（不崩溃）', () {
    fakeAsync((async) {
      final (container, player) = _makeEnv();
      container.read(themeModeProvider);
      async.flushMicrotasks();
      final notifier = container.read(sleepTimerProvider.notifier);
      notifier.start(const Duration(seconds: 5));
      // 直接销毁容器：ref.onDispose 应取消 Timer，不抛异常
      container.dispose();
      async.elapse(const Duration(seconds: 10));
      expect(player.pauseCalls, 0);
    });
  });

  test('（占位验证）ThemeModeNotifier 默认值不影响本组环境', () {
    // 保证 _makeEnv 里 override 的环境可复用：默认 dark
    fakeAsync((async) {
      final (container, _) = _makeEnv();
      addTearDown(container.dispose);
      expect(container.read(themeModeProvider), ThemeMode.dark);
      async.flushMicrotasks();
    });
  });
}
