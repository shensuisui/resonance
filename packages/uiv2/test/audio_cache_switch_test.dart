/// 播放缓存开关：ensureLoaded 必须返回持久化值（修重启后首次播放竞态）
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/providers/providers.dart';

void main() {
  test('关闭后新容器 ensureLoaded 返回 false', () async {
    final db = InMemoryDatabaseProvider();
    final c1 = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(c1.dispose);
    await c1.read(audioCacheEnabledProvider.notifier).set(false);

    final c2 = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(c2.dispose);
    expect(await c2.read(audioCacheEnabledProvider.notifier).ensureLoaded(), isFalse);
    expect(c2.read(audioCacheEnabledProvider), isFalse);
  });
}
