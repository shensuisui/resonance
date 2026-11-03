/// ShuffleBag —— 随机播放的「一轮不重复」抽签逻辑
///
/// 为什么单独测它：PlayerImpl 内部直接 new AudioPlayer()，在 flutter test 环境
/// 无平台通道、构造即抛，所以完整的随机播放流程只能在真机 integration_test 上跑。
/// 把抽签规则抽成纯逻辑之后，这里就能把「一轮内不重复」「排除当前曲目」
/// 「定种子可复现」这些关键性质钉住。
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/player.dart';

void main() {
  group('ShuffleBag', () {
    test('5 首队列（当前在 2 号）：抽 4 次各不相同、都不等于 2，抽完返回 null', () {
      final bag = ShuffleBag(rng: Random(7))..reset(5, exclude: 2);
      expect(bag.remaining, 4, reason: '当前曲目不进袋，所以只剩 4 个');

      final picked = <int>[];
      for (var i = 0; i < 4; i++) {
        final v = bag.take();
        expect(v, isNotNull);
        picked.add(v!);
      }
      expect(picked.toSet().length, 4, reason: '一轮内每首最多抽到一次');
      expect(picked, isNot(contains(2)), reason: '当前曲目不在本轮里，避免立刻重复');
      expect(bag.remaining, 0);
      expect(bag.take(), isNull, reason: '整轮抽完返回 null，由调用方重装');
    });

    test('重装是新的一轮：仍排除当前曲目', () {
      final bag = ShuffleBag(rng: Random(1))..reset(3, exclude: 0);
      bag.take();
      bag.take();
      expect(bag.remaining, 0);

      bag.reset(3, exclude: 1);
      expect(bag.remaining, 2);
      expect(bag.take(), isNot(1));
      expect(bag.take(), isNot(1));
    });

    test('单曲队列：袋里没有可抽项，返回 null（调用方负责兜底重播）', () {
      final bag = ShuffleBag()..reset(1, exclude: 0);
      expect(bag.remaining, 0);
      expect(bag.take(), isNull);
    });

    test('当前曲目越界（exclude 为 -1，例如还没起播）时，整张队列都进袋', () {
      final bag = ShuffleBag()..reset(5, exclude: -1);
      expect(bag.remaining, 5);
    });

    test('定种子可复现；换种子序列会变', () {
      List<int> run(int seed) {
        final bag = ShuffleBag(rng: Random(seed))..reset(6, exclude: 0);
        return [for (var i = 0; i < 5; i++) bag.take()!];
      }

      expect(run(42), run(42), reason: '同种子必须同序列，否则测试本身不可复现');
      expect(run(42), isNot(equals(run(43))));
    });
  });
}
