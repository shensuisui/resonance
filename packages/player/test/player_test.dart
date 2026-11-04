/// PlayerImpl 测试
///
/// 注意：just_audio 的 AudioPlayer 在 flutter test 环境无平台通道，
/// 构造即抛 AssertionError。因此 player 的完整测试（队列/播放/模式切换）
/// 需通过 integration_test 在真实设备上运行。
///
/// 本文件只验证不依赖 AudioPlayer 实例的类型契约和枚举完整性。

import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';

void main() {
  group('Player 类型契约', () {
    test('Player 是抽象类', () {
      // Player 是 abstract class，不能直接实例化
      // 验证 PlayerState 和 PlayMode 枚举完整
      expect(PlayerState.values.length, greaterThanOrEqualTo(5));
      expect(PlayMode.values.length, 4);
    });

    test('PlayerState 包含所有必要状态', () {
      expect(PlayerState.values, contains(PlayerState.idle));
      expect(PlayerState.values, contains(PlayerState.playing));
      expect(PlayerState.values, contains(PlayerState.paused));
      expect(PlayerState.values, contains(PlayerState.stopped));
      expect(PlayerState.values, contains(PlayerState.error));
    });

    test('PlayMode 包含四种播放模式', () {
      expect(PlayMode.values, contains(PlayMode.listLoop));
      expect(PlayMode.values, contains(PlayMode.singleLoop));
      expect(PlayMode.values, contains(PlayMode.shuffle));
      expect(PlayMode.values, contains(PlayMode.sequential));
    });
  });

  // PlayerImpl 实例测试需要 integration_test 环境
  // 参见 resonance_app/integration_test/ 下的播放器集成测试
  group('PlayerImpl', () {
    test('integration_test 环境运行', () {
      // 占位：PlayerImpl 的实例化、队列管理、播放模式切换、
      // 音量控制等测试在 integration_test 中执行
      expect(true, isTrue);
    });
  }, skip: 'PlayerImpl 需要 integration_test 环境（just_audio 平台通道）');
}
