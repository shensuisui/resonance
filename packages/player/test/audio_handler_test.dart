/// ResonanceAudioHandler 单元测试
///
/// 测什么：本项目 Player → audio_service 的「状态/曲目/队列」映射，以及
/// 系统命令 → Player 的转发。这里**不启动** audio_service 的平台服务
/// （AudioService.init 需要平台通道），只直接构造 handler + 假播放器，
/// 因此能在 flutter test 里跑；真机后台行为另由集成验证覆盖。
///
/// 模拟数据来源：手写 FakePlayer（可控四条流 + 记录命令调用），
/// 没有任何网络/文件/平台依赖。
library;

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/player.dart';

/// 可编程假播放器：四条流由测试手动推事件，命令调用被记录下来供断言
class FakePlayer implements Player, CurrentSongSource, AudibleSongSource {
  final stateController = StreamController<PlayerState>.broadcast();
  final positionController = StreamController<int>.broadcast();
  final durationController = StreamController<int>.broadcast();
  final songController = StreamController<Song?>.broadcast();

  /// 命令调用记录，形如 'resume' / 'seek:1000'
  final List<String> calls = <String>[];

  @override
  PlayerState currentState = PlayerState.idle;
  @override
  int currentPosition = 0;
  @override
  int currentDuration = 0;
  @override
  double volume = 1;
  @override
  PlayMode playMode = PlayMode.listLoop;
  @override
  List<Song> queue = <Song>[];
  @override
  int currentIndex = -1;

  /// 底层真实装载的那一首（PlayerImpl 也实现 AudibleSongSource）
  @override
  Song? audibleSong;

  @override
  Stream<PlayerState> get stateStream => stateController.stream;
  @override
  Stream<int> get positionStream => positionController.stream;
  @override
  Stream<int> get durationStream => durationController.stream;
  @override
  Stream<Song?> get currentSongStream => songController.stream;

  /// 推一次播放状态（同时更新快照，模拟真实播放器的一致性）
  void emitState(PlayerState state) {
    currentState = state;
    stateController.add(state);
  }

  /// 推一次「换曲」：记录在播快照并广播当前曲目（与 PlayerImpl 行为一致）
  void emitSong(Song song) {
    audibleSong = song;
    songController.add(song);
  }

  @override
  Future<void> play(Song song) async => calls.add('play:${song.globalKey}');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> resume() async => calls.add('resume');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> seek(Duration position) async =>
      calls.add('seek:${position.inMilliseconds}');
  @override
  Future<void> next() async => calls.add('next');
  @override
  Future<void> previous() async => calls.add('previous');
  @override
  Future<void> jumpToIndex(int index) async => calls.add('jump:$index');
  @override
  Future<void> setVolume(double value) async {}
  @override
  void setQueue(List<Song> songs) {}
  @override
  Future<void> prepareAt(int index, {Duration position = Duration.zero}) async {}
  @override
  Future<void> dispose() async {}

  /// 关闭全部流（测试收尾）
  Future<void> close() async {
    await stateController.close();
    await positionController.close();
    await durationController.close();
    await songController.close();
  }
}

/// 造一首歌（默认带封面与时长）
Song sampleSong({
  String id = '1',
  String sourceId = 'gequbao',
  String title = '素颜',
  String artist = '许嵩',
  String? cover = 'https://example.com/cover.jpg',
  int? duration = 259000,
}) =>
    Song(
      id: id,
      sourceId: sourceId,
      title: title,
      artist: artist,
      coverUrl: cover,
      duration: duration,
    );

/// 等事件流送达（broadcast stream 是异步投递的）
Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  group('纯映射函数', () {
    test('mapProcessingState：playing/paused 都落到 ready，靠 playing 位区分', () {
      expect(mapProcessingState(PlayerState.idle), AudioProcessingState.idle);
      expect(mapProcessingState(PlayerState.loading), AudioProcessingState.loading);
      expect(mapProcessingState(PlayerState.playing), AudioProcessingState.ready);
      expect(mapProcessingState(PlayerState.paused), AudioProcessingState.ready);
      expect(mapProcessingState(PlayerState.stopped), AudioProcessingState.idle);
      expect(mapProcessingState(PlayerState.error), AudioProcessingState.error);
    });

    test('mapRepeatMode / mapShuffleMode：四种 PlayMode 全覆盖', () {
      expect(mapRepeatMode(PlayMode.listLoop), AudioServiceRepeatMode.all);
      expect(mapRepeatMode(PlayMode.singleLoop), AudioServiceRepeatMode.one);
      expect(mapRepeatMode(PlayMode.sequential), AudioServiceRepeatMode.none);
      // 随机不改变循环语义（由 shuffleMode 单独表达）
      expect(mapRepeatMode(PlayMode.shuffle), AudioServiceRepeatMode.none);

      expect(mapShuffleMode(PlayMode.shuffle), AudioServiceShuffleMode.all);
      expect(mapShuffleMode(PlayMode.listLoop), AudioServiceShuffleMode.none);
    });

    test('buildControls：中间那颗按钮随播放态切换', () {
      final playing = buildControls(playing: true);
      expect(playing.map((c) => c.action).toList(), [
        MediaAction.custom,
        MediaAction.skipToPrevious,
        MediaAction.pause,
        MediaAction.skipToNext,
        MediaAction.custom,
      ]);
      expect(playing.first.customAction?.name, 'toggleShuffle');
      expect(playing.last.customAction?.name, 'toggleRepeat');

      final paused = buildControls(playing: false);
      expect(paused.map((c) => c.action).toList(), [
        MediaAction.custom,
        MediaAction.skipToPrevious,
        MediaAction.play,
        MediaAction.skipToNext,
        MediaAction.custom,
      ]);
    });

    test('songToMediaItem：id 用 globalKey；无封面→artUri=null；duration<=0 退回 song.duration', () {
      final song = sampleSong(cover: '  ', duration: 120000);
      final item = songToMediaItem(song);
      expect(item.id, 'gequbao:1');
      expect(item.title, '素颜');
      expect(item.artist, '许嵩');
      expect(item.artUri, isNull, reason: '空白封面不能当 URL');
      expect(item.duration, const Duration(milliseconds: 120000));

      // 播放器测得的真实时长优先于快照里的占位时长
      final withMeasured = songToMediaItem(song,
          duration: const Duration(milliseconds: 300000));
      expect(withMeasured.duration, const Duration(milliseconds: 300000));
    });
  });

  group('ResonanceAudioHandler', () {
    late FakePlayer player;
    late ResonanceAudioHandler handler;

    setUp(() {
      player = FakePlayer();
      // 与 AudioBackground.init 的自动接线一致：能提供 currentSongStream 就传进去
      handler = ResonanceAudioHandler(
        player,
        currentSongStream: player.currentSongStream,
      );
    });

    tearDown(() async {
      await handler.disposeHandler();
      await player.close();
    });

    test('初始状态：idle + 未播放 + 上一首/播放/下一首', () async {
      final state = handler.playbackState.value;
      expect(state.processingState, AudioProcessingState.idle);
      expect(state.playing, isFalse);
      final actions = state.controls.map((c) => c.action).toList();
      expect(actions, [
        MediaAction.custom,
        MediaAction.skipToPrevious,
        MediaAction.play,
        MediaAction.skipToNext,
        MediaAction.custom,
      ]);
      expect(state.controls.first.customAction?.name, 'toggleShuffle');
      expect(state.controls.last.customAction?.name, 'toggleRepeat');
    });

    test('状态流：playing → ready+playing，paused → ready+非播放', () async {
      player.emitState(PlayerState.playing);
      await flush();
      expect(handler.playbackState.value.processingState, AudioProcessingState.ready);
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.playbackState.value.controls.any((c) => c.action == MediaAction.pause), isTrue);

      player.emitState(PlayerState.paused);
      await flush();
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.controls.any((c) => c.action == MediaAction.play), isTrue);
    });

    test('状态流：loading / error 如实上报', () async {
      player.emitState(PlayerState.loading);
      await flush();
      expect(handler.playbackState.value.processingState, AudioProcessingState.loading);

      player.emitState(PlayerState.error);
      await flush();
      expect(handler.playbackState.value.processingState, AudioProcessingState.error);
    });

    test('进度流只刷新 updatePosition，不重排按钮', () async {
      player.emitState(PlayerState.playing);
      await flush();
      player.positionController.add(42000);
      await flush();
      expect(handler.playbackState.value.updatePosition,
          const Duration(milliseconds: 42000));
      expect(handler.playbackState.value.playing, isTrue);
    });

    test('当前曲目：mediaItem 带标题/歌手/时长/封面，重复事件不重复广播', () async {
      var emits = 0;
      // BehaviorSubject 会把当前值（初始 null）重放给新监听者，skip(1) 跳过它
      final sub = handler.mediaItem.skip(1).listen((_) => emits++);

      player.currentDuration = 259000;
      player.emitSong(sampleSong());
      await flush();
      final item = handler.mediaItem.value;
      expect(item, isNotNull);
      expect(item!.id, 'gequbao:1');
      expect(item.title, '素颜');
      expect(item.artist, '许嵩');
      expect(item.artUri, Uri.parse('https://example.com/cover.jpg'));
      expect(item.duration, const Duration(milliseconds: 259000));
      expect(emits, 1);

      // 同一首再推一次（内容相同）不应产生第二次广播
      player.emitSong(sampleSong());
      await flush();
      expect(emits, 1, reason: '内容未变时不应重复打平台通道');

      await sub.cancel();
    });

    test('队列：按 globalKey 广播，且只广播一次', () async {
      var emits = 0;
      final sub = handler.queue.listen((_) => emits++);

      player.queue = <Song>[sampleSong(id: '1'), sampleSong(id: '2', title: '幻听')];
      player.emitSong(sampleSong(id: '1'));
      await flush();
      expect(handler.queue.value.map((i) => i.id).toList(),
          ['gequbao:1', 'gequbao:2']);

      final before = emits;
      player.emitSong(sampleSong(id: '1'));
      await flush();
      expect(emits, before, reason: '队列未变时不应重复广播');

      await sub.cancel();
    });

    test('queueIndex 跟随 currentIndex（无当前项时为 null）', () async {
      player.queue = <Song>[sampleSong(id: '1'), sampleSong(id: '2')];
      player.currentIndex = 1;
      player.emitState(PlayerState.playing);
      await flush();
      expect(handler.playbackState.value.queueIndex, 1);

      player.currentIndex = -1;
      player.emitState(PlayerState.paused);
      await flush();
      expect(handler.playbackState.value.queueIndex, isNull);
    });

    test('命令转发：play/pause/stop/seek/next/previous 一一对应', () async {
      await handler.play();
      await handler.pause();
      await handler.stop();
      await handler.seek(const Duration(milliseconds: 1500));
      await handler.skipToNext();
      await handler.skipToPrevious();
      expect(player.calls,
          ['resume', 'pause', 'stop', 'seek:1500', 'next', 'previous']);
    });

    test('stop() 之后面板主动置为 idle+非播放（系统不一定回推状态）', () async {
      player.emitState(PlayerState.playing);
      await flush();
      await handler.stop();
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.processingState, AudioProcessingState.idle);
    });

    test('skipToQueueItem：合法下标跳转，越界忽略', () async {
      player.queue = <Song>[sampleSong(id: '1'), sampleSong(id: '2')];
      await handler.skipToQueueItem(1);
      await handler.skipToQueueItem(9);
      await handler.skipToQueueItem(-1);
      expect(player.calls, ['jump:1']);
    });

    test('playMediaItem：队列里有的直接播那一首', () async {
      final song = sampleSong(id: '7', title: '山水之间');
      player.queue = <Song>[song];
      await handler.playMediaItem(MediaItem(id: 'gequbao:7', title: '山水之间'));
      expect(player.calls, ['play:gequbao:7']);
    });

    test('playMediaItem：队列里没有时用 MediaItem 字段重建 Song', () async {
      await handler.playMediaItem(MediaItem(
        id: 'fengye:88',
        title: '若把你',
        artist: '小霞',
        album: '单曲',
        duration: const Duration(seconds: 200),
      ));
      expect(player.calls, ['play:fengye:88']);
    });

    test('playMediaItem：id 不是 sourceId:id 形态时安全忽略', () async {
      await handler.playMediaItem(const MediaItem(id: 'nonsense', title: 'x'));
      expect(player.calls, isEmpty);
    });

    test('playFromMediaId 走同一条点播路径', () async {
      player.queue = <Song>[sampleSong(id: '3')];
      await handler.playFromMediaId('gequbao:3');
      expect(player.calls, ['play:gequbao:3']);
    });

    test('没有当前曲目流时，状态变化会兜底刷新曲目与队列', () async {
      // 某些 Player 实现不实现 CurrentSongSource：此时只能靠状态变化刷新
      final plainHandler = ResonanceAudioHandler(player);
      player.queue = <Song>[sampleSong(id: '5', title: '幻听')];
      player.currentIndex = 0;
      player.currentDuration = 243000;
      player.emitState(PlayerState.playing);
      await flush();

      expect(plainHandler.mediaItem.value?.id, 'gequbao:5');
      expect(plainHandler.queue.value.length, 1);
      expect(plainHandler.playbackState.value.playing, isTrue);
      await plainHandler.disposeHandler();
    });

    test('setRepeatMode / setShuffleMode 写回 Player.playMode 并刷新面板', () async {
      await handler.setRepeatMode(AudioServiceRepeatMode.one);
      expect(player.playMode, PlayMode.singleLoop);
      expect(handler.playbackState.value.repeatMode, AudioServiceRepeatMode.one);

      await handler.setRepeatMode(AudioServiceRepeatMode.none);
      expect(player.playMode, PlayMode.sequential);

      await handler.setShuffleMode(AudioServiceShuffleMode.all);
      expect(player.playMode, PlayMode.shuffle);
      expect(handler.playbackState.value.shuffleMode, AudioServiceShuffleMode.all);

      await handler.setShuffleMode(AudioServiceShuffleMode.none);
      expect(player.playMode, PlayMode.listLoop);
    });
    test('自定义通知按钮：随机/循环切换 playMode', () async {
      await handler.customAction('toggleShuffle');
      expect(player.playMode, PlayMode.shuffle);
      await handler.customAction('toggleShuffle');
      expect(player.playMode, PlayMode.listLoop);

      await handler.customAction('toggleRepeat');
      expect(player.playMode, PlayMode.singleLoop);
      await handler.customAction('toggleRepeat');
      expect(player.playMode, PlayMode.listLoop);
    });
  });
}
