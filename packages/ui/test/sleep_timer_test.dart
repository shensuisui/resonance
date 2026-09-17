/// SleepTimerNotifier 睡眠定时器测试（阶段三 14）
///
/// 用 fake_async 推进虚拟时钟，验证：
/// 1. start 后按秒递减，到点暂停播放并清空状态
/// 2. cancel 清空状态且不再触发暂停
/// 3. 重新 start 覆盖旧倒计时
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:ui/ui.dart';

class _FakePlayer implements Player {
  int pauseCalls = 0;

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test('start 后按秒递减，到点暂停播放并清空', () {
    fakeAsync((async) {
      final player = _FakePlayer();
      final container = ProviderContainer(overrides: [
        playerProvider.overrideWith((ref) => player),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(sleepTimerProvider.notifier);
      notifier.start(const Duration(seconds: 3));
      expect(container.read(sleepTimerProvider), const Duration(seconds: 3));

      async.elapse(const Duration(seconds: 1));
      expect(container.read(sleepTimerProvider), const Duration(seconds: 2));

      // 继续推进到超时（3 秒总时长）
      async.elapse(const Duration(seconds: 3));
      expect(container.read(sleepTimerProvider), isNull,
          reason: '到点后状态清空');
      expect(player.pauseCalls, 1, reason: '到点暂停播放一次');
    });
  });

  test('cancel 清空状态且不再暂停', () {
    fakeAsync((async) {
      final player = _FakePlayer();
      final container = ProviderContainer(overrides: [
        playerProvider.overrideWith((ref) => player),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(sleepTimerProvider.notifier);
      notifier.start(const Duration(seconds: 5));
      notifier.cancel();
      expect(container.read(sleepTimerProvider), isNull);

      async.elapse(const Duration(seconds: 10));
      expect(player.pauseCalls, 0);
    });
  });

  test('重新 start 覆盖旧倒计时', () {
    fakeAsync((async) {
      final player = _FakePlayer();
      final container = ProviderContainer(overrides: [
        playerProvider.overrideWith((ref) => player),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(sleepTimerProvider.notifier);
      notifier.start(const Duration(seconds: 30));
      async.elapse(const Duration(seconds: 10));
      notifier.start(const Duration(seconds: 5));
      expect(container.read(sleepTimerProvider), const Duration(seconds: 5));

      async.elapse(const Duration(seconds: 4));
      expect(container.read(sleepTimerProvider), const Duration(seconds: 1));
      async.elapse(const Duration(seconds: 2));
      expect(container.read(sleepTimerProvider), isNull);
      expect(player.pauseCalls, 1);
    });
  });
}
