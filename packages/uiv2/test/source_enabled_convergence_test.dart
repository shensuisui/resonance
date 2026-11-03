/// 源启用状态「收敛成一份真相」的回归测试
///
/// 收敛前：UI 侧另存了一份 Map<String,bool>，与 SourceManager 内部的 _enabledStatus 并存。
/// 只要有一条路径绕过 UI 直接改 manager（启动时注册内置源、订阅库加载新源都这么做），
/// 界面就会失真：源实际在参与搜索，列表里却显示「已停用」。
/// 现在真值只有 manager，UI 只观察版本号。这里钉四件事：
///   ① 直接改 manager（完全绕过 UI 入口）时，enabledSourcesProvider 必须立刻反映；
///   ② SourceEnabledActions.set 切换时，manager 与 settings 都要更新；
///   ③ 启动恢复：settings 里的 source_enabled_<id> 会应用回 manager；
///   ④ 状态没变时不重复通知（避免无谓重建）。
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:uiv2/src/providers/providers.dart';

/// 只需要 sourceInfo 的假源
class _FakeSource implements MusicSource {
  @override
  final SourceInfo sourceInfo;

  _FakeSource(String id, String name, {required bool enabled})
      : sourceInfo = SourceInfo(
          id: id,
          name: name,
          type: SourceType.values.first,
          enabled: enabled,
        );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 造一个注册好两个源的 manager：a 默认停用、b 默认启用
SourceManager _manager() => SourceManager()
  ..registerSource(_FakeSource('a', 'A源', enabled: false))
  ..registerSource(_FakeSource('b', 'B源', enabled: true));

/// 已启用源的 id 集合
Set<String> _enabledIds(ProviderContainer c) =>
    c.read(enabledSourcesProvider).map((s) => s.sourceInfo.id).toSet();

void main() {
  late InMemoryDatabaseProvider db;
  late SourceManager manager;
  late ProviderContainer container;

  setUp(() async {
    db = InMemoryDatabaseProvider();
    await db.initialize();
    manager = _manager();
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        sourceManagerProvider.overrideWithValue(manager),
      ],
    );
    addTearDown(container.dispose);
    // 触发版本 notifier 的 build：挂上 onEnabledChanged 回调 + 懒恢复
    container.read(enabledSourcesProvider);
  });

  test('绕过 UI 直接改 manager：视图立刻反映（这就是「一份真相」）', () {
    expect(_enabledIds(container), {'b'});

    // 模拟 main_v2 / 订阅库：不走任何 UI 入口，直接改 manager
    manager.setSourceEnabled('a', true);

    expect(_enabledIds(container), {'a', 'b'},
        reason: 'manager 是真值：它变了视图必须跟着变，不该等谁去同步第二份状态');
  });

  test('SourceEnabledActions.set：manager 与 settings 都更新', () async {
    await container.read(sourceEnabledActionsProvider).set('a', true);
    expect(manager.isSourceEnabled('a'), isTrue);
    expect(await db.settingsDao.get('source_enabled_a'), '1');
    expect(_enabledIds(container), {'a', 'b'});
  });

  test('启动恢复：settings 里的停用会应用回 manager', () async {
    await db.settingsDao.set('source_enabled_b', '0');

    // 新 manager + 新容器 = 模拟重启（b 在源定义里默认启用）
    final fresh = _manager();
    final c2 = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        sourceManagerProvider.overrideWithValue(fresh),
      ],
    );
    addTearDown(c2.dispose);
    c2.read(enabledSourcesProvider); // 触发懒恢复
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(fresh.isSourceEnabled('b'), isFalse,
        reason: 'settings 里是 0，重启后必须停用（否则用户的选择没落地）');
    expect(_enabledIds(c2), isEmpty, reason: 'a 本来就停用、b 被恢复成停用');
  });

  test('状态没变时不重复通知（避免无谓重建）', () {
    final v0 = container.read(sourceEnabledVersionProvider);
    manager.setSourceEnabled('b', true); // 已经是 true
    expect(container.read(sourceEnabledVersionProvider), v0);

    manager.setSourceEnabled('b', false);
    expect(container.read(sourceEnabledVersionProvider), v0 + 1);
  });
}
