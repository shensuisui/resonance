/// PlayerImpl 真实播放语义测试
///
/// 为什么需要这组测试：just_audio 的 `AudioPlayer.play()` 返回的 Future
/// **不是“已经起播”的信号**，而是等到播放完成 / 暂停 / 停止才完成。Android
/// 原生实现甚至会暂存 playResult，导致暂停后第一次点播放时声音已经恢复、
/// 但 `resume()` 仍停在 await，播放器状态和 UI 图标都还停留在 paused。
///
/// 这里用 just_audio 官方 Platform Interface 搭一个“play() 不立即完成”的
/// 平台假实现，让真实的 [AudioPlayer] 跑在测试里；这样验证的是产品实际依赖
/// 的 Future 语义，而不是一个“resume 立即返回”的桩。
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:player/player.dart';

/// 让下一次平台 load 永不返回（模拟插件把错误发到非平台线程后 Future 悬挂）
bool _hangLoad = false;

/// 模拟 Android 播放服务的平台实现。
///
/// 关键点：[play] 返回的 Future 持有到 [pause] 才完成，复刻 just_audio
/// 文档里 “completes when the playback completes or is paused or stopped”。
class _FakeAudioPlayerPlatform extends AudioPlayerPlatform {
  _FakeAudioPlayerPlatform(super.id);

  final _events = StreamController<PlaybackEventMessage>.broadcast();
  final _playCompleter = <Completer<PlayResponse>>[];

  ProcessingStateMessage _processingState = ProcessingStateMessage.idle;
  Duration _position = Duration.zero;
  final Duration _duration = const Duration(minutes: 3);

  /// 当前是否还有未完成的 play 请求（测试断言用）
  bool get hasPendingPlay => _playCompleter.isNotEmpty;

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      _events.stream;

  void _emit() {
    if (_events.isClosed) return;
    _events.add(PlaybackEventMessage(
      processingState: _processingState,
      updateTime: DateTime.now(),
      updatePosition: _position,
      bufferedPosition: _position,
      duration: _duration,
      icyMetadata: null,
      currentIndex: 0,
      androidAudioSessionId: null,
    ));
  }

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    if (_hangLoad) return Completer<LoadResponse>().future;
    _processingState = ProcessingStateMessage.ready;
    _emit();
    return LoadResponse(duration: _duration);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) {
    // 声音开始走：进度推进，供 PlayerImpl 的首播自愈逻辑判断
    _position = const Duration(seconds: 1);
    _emit();
    final completer = Completer<PlayResponse>();
    _playCompleter.add(completer);
    return completer.future;
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    // 与真实实现一致：暂停会让挂起的 play() Future 完成
    for (final completer in _playCompleter) {
      if (!completer.isCompleted) completer.complete(PlayResponse());
    }
    _playCompleter.clear();
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    final target = request.position;
    if (target != null) {
      _position = target;
      _emit();
    }
    return SeekResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async =>
      SetPitchResponse();

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(
          SetSkipSilenceRequest request) async =>
      SetSkipSilenceResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
          SetShuffleModeRequest request) async =>
      SetShuffleModeResponse();

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    for (final completer in _playCompleter) {
      if (!completer.isCompleted) completer.complete(PlayResponse());
    }
    _playCompleter.clear();
    await _events.close();
    return DisposeResponse();
  }
}

class _FakeJustAudioPlatform extends JustAudioPlatform {
  _FakeAudioPlayerPlatform? player;

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final platform = _FakeAudioPlayerPlatform(request.id);
    player = platform;
    return platform;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeJustAudioPlatform fakePlatform;
  late PlayerImpl player;

  const song = Song(
    id: 'a',
    sourceId: 'stub',
    title: '测试曲目',
    artist: '测试歌手',
    playUrl: 'https://example.invalid/a.mp3',
  );

  setUp(() {
    fakePlatform = _FakeJustAudioPlatform();
    JustAudioPlatform.instance = fakePlatform;
    player = PlayerImpl();
  });

  tearDown(() async {
    await player.dispose();
  });

  test('暂停后第一次 resume：命令发出即进入 playing，不等待 play() 完成', () async {
    player.setQueue([song]);
    await player.prepareAt(0).timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail('prepareAt 卡住了'),
        );
    expect(player.currentState, PlayerState.paused, reason: '预置只装载不出声');

    final states = <PlayerState>[];
    final sub = player.stateStream.listen(states.add);

    // 旧实现会 await play()，而假平台的 play() 要等 pause 才完成 → 这里会超时
    await player.resume().timeout(
          const Duration(milliseconds: 300),
          onTimeout: () => fail('resume() 等 play() 完成，Android 上就是按钮不同步的根因'),
        );

    expect(player.currentState, PlayerState.playing, reason: '声音恢复后状态必须同步');
    await Future<void>.delayed(Duration.zero);
    expect(states, contains(PlayerState.playing));

    await sub.cancel();
  });

  test('连续播放 → 暂停 → 播放：每次单击状态都正确切换', () async {
    player.setQueue([song]);

    await player.play(song).timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail('播放卡在 await play()'),
        );
    expect(player.currentState, PlayerState.playing);

    await player.pause().timeout(const Duration(seconds: 1));
    expect(player.currentState, PlayerState.paused);

    await player.resume().timeout(
          const Duration(milliseconds: 300),
          onTimeout: () => fail('暂停后首次播放卡住了'),
        );
    expect(player.currentState, PlayerState.playing);

    await player.pause().timeout(const Duration(seconds: 1));
    expect(player.currentState, PlayerState.paused);
  });

  test('装载超时会重建底层播放器，后续点歌不再被串行队列锁死', () async {
    final fast = PlayerImpl(
      fileLoadTimeout: const Duration(milliseconds: 80),
      networkLoadTimeout: const Duration(milliseconds: 80),
    );
    addTearDown(fast.dispose);

    _hangLoad = true;
    final bad = song.copyWith(playUrl: 'file:///C:/中文目录/坏文件.mp3');
    fast.setQueue([bad]);

    await fast.play(bad).timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail('插件永不返回时播放器没有超时恢复'),
        );
    expect(fast.currentState, PlayerState.error);

    _hangLoad = false;
    await fast.play(song).timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail('超时后串行队列仍被旧 AudioPlayer 锁死'),
        );
    expect(fast.currentState, PlayerState.playing);
  });

  test('快速重复 resume 不会让状态过期或按钮与声音不一致', () async {
    player.setQueue([song]);
    await player.prepareAt(0);

    await Future.wait([
      player.resume(),
      player.resume(),
      player.resume(),
    ]).timeout(
      const Duration(milliseconds: 300),
      onTimeout: () => fail('快速重复 resume 卡住了'),
    );
    expect(player.currentState, PlayerState.playing);

    await player.pause().timeout(const Duration(seconds: 1));
    expect(player.currentState, PlayerState.paused);
  });
}
