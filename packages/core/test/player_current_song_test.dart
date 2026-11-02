/// 「当前曲目」契约测试（回归：真机点歌失败后在播的那首从播放条消失）
///
/// 现场症状：A 正在正常播放，点一首播不出来的 B（源取不到地址）：
///   * B 没能播放（正确）；
///   * 但播放条上 A 也消失了（错误）；
///   * 而声音还在放 A（错误 —— UI 与声音脱节）。
///
/// 根因：换队列时 PlayerImpl 把索引清成 -1 并广播，而"当前曲目"是由
/// 「索引 → 队列」推导出来的，于是推导得到 null。
/// 修法：播放器如实报出「底层音源真正加载的那一首」（AudibleSongSource），
/// 「当前曲目」优先听它。这里把这条契约钉死。
///
/// 模拟数据：用 noSuchMethod 的假播放器（只需声明 queue / currentIndex /
/// audibleSong 三件事），不依赖 just_audio 平台通道。
library;

import 'package:core/core.dart';
import 'package:test/test.dart';

/// 假播放器：只声明与本契约相关的三件事，其余成员交给 noSuchMethod
class _FakePlayer implements Player, AudibleSongSource {
  /// 构造
  _FakePlayer({required this.queue, required this.currentIndex, this.audibleSong});

  @override
  final List<Song> queue;

  @override
  final int currentIndex;

  @override
  final Song? audibleSong;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 只声明队列/索引的假播放器（不实现 AudibleSongSource，验证零破坏）
class _PlainFakePlayer implements Player {
  /// 构造
  _PlainFakePlayer({required this.queue, required this.currentIndex});

  @override
  final List<Song> queue;

  @override
  final int currentIndex;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  /// 正在播放的 A
  const a = Song(
      id: 'a', sourceId: 's', title: 'A', artist: '歌手A', playUrl: 'http://a.mp3');

  /// 点了但播不出来的 B
  const b = Song(id: 'b', sourceId: 's', title: 'B', artist: '歌手B');

  group('当前曲目（PlayerCurrentSong）', () {
    test('换了队列，在播的仍是 A：当前曲目必须报 A，不能报 null', () {
      // 现场：队列已被换成 [B]、索引为 -1（旧实现广播 null 的取值）
      final player = _FakePlayer(queue: const [b], currentIndex: -1, audibleSong: a);

      expect(player.currentSong, a, reason: '声音还在放 A，UI 不能凭空清空');
    });

    test('在播的 A 已不在新队列里：仍要报 A（而不是索引推导出的 B/null）', () {
      final player = _FakePlayer(queue: const [b], currentIndex: 0, audibleSong: a);

      expect(player.currentSong, a, reason: '以底层真正加载的为准');
    });

    test('没有在播曲目时：退回索引推导（队列里索引指向的那首）', () {
      final player = _FakePlayer(queue: const [a, b], currentIndex: 1);

      expect(player.currentSong, b);
    });

    test('不实现 AudibleSongSource 的播放器：行为与旧版一致（零破坏）', () {
      final player = _PlainFakePlayer(queue: const [a, b], currentIndex: 0);

      expect(player.currentSong, a);
    });

    test('索引越界：报 null（不抛异常）', () {
      final player = _PlainFakePlayer(queue: const [a], currentIndex: 3);

      expect(player.currentSong, isNull);
    });
  });
}
