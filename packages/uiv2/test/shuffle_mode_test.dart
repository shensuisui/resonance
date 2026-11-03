/// 随机播放（收敛到播放模式）的回归测试
///
/// 背景（用户报「随机播放没生效」）：uiv2 曾经把随机做成独立的 ShuffleNotifier，
/// 它的 set/toggle 只写自己的 bool、**从不同步给播放器**；而 PlayModeNotifier.cycle()
/// 又主动跳过 shuffle，于是 uiv2 里没有任何路径能把 PlayMode.shuffle 交给播放器 ——
/// 播放条上的随机按钮看着是开的，实际一直在顺序播放。
///
/// 这里钉三件事：
///   ① shuffleProvider 是 playModeProvider 的派生视图（不再有第二份状态）；
///   ② 开/关随机都会同步给播放器（当初缺的就是这根线）；
///   ③ 关闭随机回到「进入随机前的循环模式」。
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:uiv2/src/providers/providers.dart';

/// 记录被写入的播放模式：随机播放是否真的到达播放器，全靠它取证
class _RecordingPlayer implements Player {
  /// 最近一次被设置的播放模式
  PlayMode? mode;

  @override
  set playMode(PlayMode value) => mode = value;

  @override
  PlayMode get playMode => mode ?? PlayMode.listLoop;

  @override
  Stream<PlayerState> get stateStream => const Stream.empty();

  @override
  Stream<int> get positionStream => const Stream.empty();

  @override
  Stream<int> get durationStream => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late InMemoryDatabaseProvider db;
  late _RecordingPlayer player;
  late ProviderContainer container;

  setUp(() async {
    db = InMemoryDatabaseProvider();
    await db.initialize();
    player = _RecordingPlayer();
    container = ProviderContainer(overrides: <Override>[
      appDatabaseProvider.overrideWithValue(db),
      playerProvider.overrideWithValue(player),
    ]);
    addTearDown(container.dispose);
    // 走一遍 load（读 settings 并同步给播放器），与真实启动时序一致
    await container.read(playModeProvider.notifier).load();
  });

  test('随机开关是播放模式的派生视图', () async {
    expect(container.read(shuffleProvider), isFalse);
    await container.read(playModeProvider.notifier).set(PlayMode.shuffle);
    expect(container.read(shuffleProvider), isTrue);
    await container.read(playModeProvider.notifier).set(PlayMode.listLoop);
    expect(container.read(shuffleProvider), isFalse);
  });

  test('开启随机必须同步给播放器（当初缺的就是这根线）', () async {
    await container.read(playModeProvider.notifier).setShuffle(true);
    expect(player.mode, PlayMode.shuffle,
        reason: '播放器必须真的进入随机模式，否则下一首仍按顺序走');
    expect(await db.settingsDao.get(PlayModeNotifier.key), 'shuffle');
  });

  test('关闭随机回到进入随机前的循环模式', () async {
    await container.read(playModeProvider.notifier).set(PlayMode.singleLoop);
    await container.read(playModeProvider.notifier).setShuffle(true);
    expect(player.mode, PlayMode.shuffle);

    await container.read(playModeProvider.notifier).setShuffle(false);
    expect(container.read(playModeProvider), PlayMode.singleLoop);
    expect(player.mode, PlayMode.singleLoop, reason: '播放器也要跟着回到单曲循环');
  });

  test('随机模式里重复开启，不得把「之前的模式」覆盖成随机', () async {
    await container.read(playModeProvider.notifier).set(PlayMode.sequential);
    await container.read(playModeProvider.notifier).setShuffle(true);
    await container.read(playModeProvider.notifier).setShuffle(true);
    await container.read(playModeProvider.notifier).setShuffle(false);
    expect(container.read(playModeProvider), PlayMode.sequential,
        reason: '必须回到顺序播放，而不是卡在随机');
  });

  test('关闭随机时若当前不是随机，模式保持不变', () async {
    await container.read(playModeProvider.notifier).set(PlayMode.listLoop);
    await container.read(playModeProvider.notifier).setShuffle(false);
    expect(container.read(playModeProvider), PlayMode.listLoop);
    expect(player.mode, PlayMode.listLoop);
  });
}
