/// 播放页顶部那行字的测试（「正在播放」下面显示什么）
///
/// 用户要求：这里显示**播放队列的名字**（默认1 / 最近播放 / 我喜欢的音乐…），
/// 而不是一个占位的破折号；有睡眠倒计时时并列显示。
///
/// 这是纯函数，直接单测，不用 pump 整个播放页。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/components/now_playing.dart';

void main() {
  group('nowPlayingContextLine', () {
    test('有队列：显示队列名字', () {
      expect(
        nowPlayingContextLine(
          pending: false,
          queueTitle: '默认1',
          hasQueue: true,
          sleep: null,
        ),
        '默认1',
      );
      expect(
        nowPlayingContextLine(
          pending: false,
          queueTitle: '最近播放',
          hasQueue: true,
          sleep: null,
        ),
        '最近播放',
      );
    });

    test('睡眠倒计时与队列名并列', () {
      expect(
        nowPlayingContextLine(
          pending: false,
          queueTitle: '默认1',
          hasQueue: true,
          sleep: const Duration(seconds: 90),
        ),
        contains('默认1'),
      );
    });

    test('还没播过任何东西：退回占位符（不显示空串）', () {
      expect(
        nowPlayingContextLine(
          pending: false,
          queueTitle: '',
          hasQueue: false,
          sleep: null,
        ),
        '—',
      );
    });

    test('正在准备播放时以状态优先', () {
      expect(
        nowPlayingContextLine(
          pending: true,
          queueTitle: '默认1',
          hasQueue: true,
          sleep: null,
        ),
        '准备播放中',
      );
    });
  });
}
