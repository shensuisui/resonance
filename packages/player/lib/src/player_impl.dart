import 'dart:async';

import 'package:core/core.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;

/// 基于 just_audio 的播放器实现
class PlayerImpl implements AudibleSongSource, Player, CurrentSongSource {
  final AudioPlayer _audioPlayer = AudioPlayer();

  /// 队列里的曲目常常只有 id（来自最近播放/歌单快照，没有 playUrl）。
  /// 真正播放前用它现取一次地址；取到后写回队列，避免重复请求。
  final Future<String> Function(Song song)? urlResolver;

  List<Song> _queue = [];
  int _currentIndex = -1;

  /// 底层音源**真正加载**的那一首（与 [_currentIndex] 分开维护）
  ///
  /// 为什么单独存：换队列只改 Dart 侧列表、底层音源并没停，索引推导会把在播的
  /// 那首推导成 null（真机症状：点了首歌播不出来，播放条上在播的那首消失、
  /// 但声音还在放）。这里如实记录"声音是谁的"，UI 才不会与声音脱节。
  Song? _audibleSong;
  PlayMode _playMode = PlayMode.listLoop;
  final List<int> _shuffleHistory = [];

  /// 播放请求令牌：只有最后一次请求的结果允许提交（后发优先）
  int _playToken = 0;

  /// 正在切换音频源：这期间上报的 completed 是上一个源的状态残留，
  /// 不能当作"这首播完了"，否则会连环自动下一首（实测 2 秒跳 9 首）
  bool _loading = false;

  /// 串行队列：同一个 AudioPlayer 上不允许两个 setAudioSource 交错
  Future<void> _serial = Future<void>.value();

  PlayerState _currentState = PlayerState.idle;
  int _currentPosition = 0;
  int _currentDuration = 0;
  double _volume = 1.0;

  final _stateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<int>.broadcast();
  final _durationController = StreamController<int>.broadcast();

  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  final _currentSongController = StreamController<Song?>.broadcast();

  PlayerImpl({this.urlResolver}) {
    _setupListeners();
  }

  void _setupListeners() {
    _playerStateSub = _audioPlayer.playerStateStream.listen((state) {
      switch (state.processingState) {
        case ProcessingState.idle:
          _updateState(PlayerState.idle);
        case ProcessingState.loading:
          _updateState(PlayerState.loading);
        case ProcessingState.buffering:
          // 缓冲中保持当前状态
        case ProcessingState.ready:
          if (_currentState == PlayerState.loading) {
            _updateState(PlayerState.playing);
          }
        case ProcessingState.completed:
          _onTrackCompleted();
      }
    });

    _positionSub = _audioPlayer.positionStream.listen((position) {
      _currentPosition = position.inMilliseconds;
      _positionController.add(_currentPosition);
    });

    _durationSub = _audioPlayer.durationStream.listen((duration) {
      _currentDuration = duration?.inMilliseconds ?? 0;
      _durationController.add(_currentDuration);
    });

    // 注意：完成事件只在 _playerStateSub 的 completed 分支里处理，
    // 这里原来又订阅了一次 processingStateStream.completed，
    // 导致一次播放结束触发两次 next()（"点 A 播 B"的直接原因之一）。
  }

  void _onTrackCompleted() {
    if (_queue.isEmpty) return;
    // 只有"真的在播并且播完"才算切下一首；加载中/暂停/出错都不切
    if (_loading) return;
    if (_currentState != PlayerState.playing) return;

    switch (_playMode) {
      case PlayMode.singleLoop:
        _playIndex(_currentIndex);
      case PlayMode.shuffle:
        _playNextShuffle();
      case PlayMode.listLoop:
        _playNextListLoop();
      case PlayMode.sequential:
        if (_currentIndex < _queue.length - 1) {
          _playIndex(_currentIndex + 1);
        } else {
          _updateState(PlayerState.stopped);
        }
    }
  }

  void _playNextListLoop() {
    final nextIndex = (_currentIndex + 1) % _queue.length;
    _playIndex(nextIndex);
  }

  void _playNextShuffle() {
    if (_queue.length <= 1) {
      _playIndex(0);
      return;
    }
    int nextIndex;
    do {
      nextIndex = DateTime.now().microsecondsSinceEpoch % _queue.length;
    } while (nextIndex == _currentIndex);

    _shuffleHistory.add(_currentIndex);
    _playIndex(nextIndex);
  }

  /// 串行化入口：把并发点播/上一首/下一首排成一条线，过期请求直接丢弃
  Future<void> _playIndex(int index) {
    final token = ++_playToken;
    final next = _serial.then((_) async {
      if (token != _playToken) return; // 已经有更新的播放请求，这一条作废
      await _doPlayIndex(index, token);
    });
    _serial = next.catchError((Object _) {});
    return next;
  }

  @override
  Future<void> prepareAt(int index, {Duration position = Duration.zero}) {
    final token = ++_playToken;
    final next = _serial.then((_) async {
      if (token != _playToken) return;
      await _doPlayIndex(index, token, autoplay: false);
      if (token != _playToken) return;
      if (position <= Duration.zero) return;
      // 装载成功才 seek：源没给地址时 _doPlayIndex 已经回滚，不能在这里硬定位
      try {
        await _audioPlayer.seek(position);
        _currentPosition = position.inMilliseconds;
        _positionController.add(_currentPosition);
      } catch (e) {
        SourceLogBus.instance.emit(
            _queue[index].sourceId, SourceLogLevel.warn, '播放器',
            '预置进度定位失败（不影响播放）: $e');
      }
    });
    _serial = next.catchError((Object _) {});
    return next;
  }

  Future<void> _doPlayIndex(int index, int token, {bool autoplay = true}) async {
    if (index < 0 || index >= _queue.length) return;
    _loading = true;
    _currentIndex = index;
    var song = _queue[index];
    _updateState(PlayerState.loading);
    final sw = Stopwatch()..start();
    var url = song.playUrl ?? '';
    // 队列里没有地址（最近播放/歌单快照就是这种）→ 现取一次并写回队列
    if (url.isEmpty && urlResolver != null) {
      try {
        url = await urlResolver!(song);
      } catch (e) {
        SourceLogBus.instance.emit(
            song.sourceId, SourceLogLevel.error, '播放器', '取播放地址失败: $e');
        url = '';
      }
      if (url.isNotEmpty) {
        song = song.copyWith(playUrl: url);
        _queue[index] = song;
      }
    }
    SourceLogBus.instance.emit(
      song.sourceId, SourceLogLevel.info, '播放器',
      '播放 idx=$index id=${song.id} url=$url');
    // 空地址绝不能提交给播放器：just_audio_windows 收到空 URI 会直接让进程崩掉
    // （实测：源返回空地址 → 应用 Lost connection to device）。
    // 这里回滚索引并如实报错，既不假装在播，也不把空地址丢给底层。
    if (url.isEmpty) {
      SourceLogBus.instance.emit(song.sourceId, SourceLogLevel.warn, '播放器',
          'id=${song.id} 源未提供播放地址，跳过加载（避免空地址导致崩溃）');
      // 回到"真正在播的那一首"（底层音源没动过，UI 不能凭空清空）
      if (token == _playToken) {
        _syncIndexToAudible();
        _emitCurrentSong();
      }
      _updateState(PlayerState.error);
      _loading = false;
      return;
    }
    try {
      await _audioPlayer.setAudioSource(
          AudioSource.uri(Uri.parse(url)),
          preload: true);
      // 加载期间如果又来了新的播放请求，就不要再提交这一条（否则 UI 会停在过期的曲目）
      if (token != _playToken) return;
      // 关键：音频源真的被播放器接受之后才广播，并记下"在播的就是它"。
      // 之前在改 _currentIndex 时就广播，一旦加载失败/超时，UI 已是新歌、
      // 实际还在放上一首 —— 这正是"页面显示 A、实际播 B"的成因。
      _audibleSong = song;
      _emitCurrentSong();
      SourceLogBus.instance.emit(
        song.sourceId, SourceLogLevel.info, '播放器',
        'setAudioSource 完成（${sw.elapsedMilliseconds}ms），状态=${_audioPlayer.processingState.name}');

      // 关键：等待底层加载完成（ready）再发 play 请求。
      // just_audio_windows 在 source 加载完成前调用 play() 会被忽略
      // （Play() no-op，日志看不到 Called play），导致"已取到时长却不播放"。
      if (_audioPlayer.processingState != ProcessingState.ready) {
        await _audioPlayer.processingStateStream
            .firstWhere((s) => s == ProcessingState.ready)
            .timeout(const Duration(seconds: 15));
        SourceLogBus.instance.emit(
          song.sourceId, SourceLogLevel.info, '播放器',
          '等待加载完成（共 ${sw.elapsedMilliseconds}ms）→ play()');
      }

      if (!autoplay) {
        // 预置（启动恢复 / 继续播放）：音源装好、位置摆好，但**不出声**
        _updateState(PlayerState.paused);
        SourceLogBus.instance.emit(
          song.sourceId, SourceLogLevel.info, '播放器',
          '已预置 idx=$index id=${song.id}（等待用户按播放）');
        return;
      }
      await _audioPlayer.play();
      SourceLogBus.instance.emit(
        song.sourceId, SourceLogLevel.info, '播放器',
        'play() 完成（${sw.elapsedMilliseconds}ms），状态=${_currentState.name}');
      _updateState(PlayerState.playing);
      // 冷启动首播：just_audio_windows 偶尔会忽略第一次 play()，
      // 现象是封面/标题都换了但进度条一直 0:00 —— 这里校验并自愈。
      await _ensureProgressing(song.sourceId, token);
    } catch (e, st) {
      SourceLogBus.instance.emit(
        song.sourceId, SourceLogLevel.error, '播放器',
        '播放失败 idx=$index id=${song.id} url=$url: $e\n$st');
      // 回滚：音频没切成功，索引退回，UI 跟着退回真正在播的那一首。
      // 只有仍是"当前请求"时才回滚，避免覆盖后来者的状态。
      if (token == _playToken) {
        _syncIndexToAudible();
        _emitCurrentSong();
      }
      _updateState(PlayerState.error);
    } finally {
      // 无论成功失败都要解除"加载中"，否则完成事件闸门会一直关着
      _loading = false;
    }
  }

  /// 确认音频真的在走（进度推进），必要时重发 play() / 重设音频源
  ///
  /// 背景：桌面端冷启动第一次 setAudioSource 后 play() 可能被底层忽略，
  /// UI 已经显示新曲目，但 position 永远是 0，用户看到"点了不播"。
  Future<void> _ensureProgressing(String sourceId, int token) async {
    // 先给 1.5s 正常起播时间（含解码器初始化）
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (token != _playToken) return;
      if (_audioPlayer.position > Duration.zero) return;
      if (_currentState != PlayerState.playing) return;
    }

    // 还没动：重发 play()
    SourceLogBus.instance.emit(
        sourceId, SourceLogLevel.info, '播放器', '首播 1.5s 进度仍为 0，重发 play()');
    for (var i = 0; i < 4; i++) {
      await _audioPlayer.play();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (token != _playToken) return;
      if (_audioPlayer.position > Duration.zero) {
        SourceLogBus.instance.emit(
            sourceId, SourceLogLevel.info, '播放器', '重发 play() 后已开始推进');
        return;
      }
    }

    // 仍然不动：重设一次音频源再播（解器/管道没就绪的兜底）
    if (token != _playToken) return;
    final index = _currentIndex;
    if (index < 0 || index >= _queue.length) return;
    final url = _queue[index].playUrl ?? '';
    if (url.isEmpty) return;
    SourceLogBus.instance.emit(
        sourceId, SourceLogLevel.info, '播放器', '重发 play() 无效，重设音频源再播');
    await _audioPlayer.setAudioSource(
      AudioSource.uri(Uri.parse(url)),
      preload: true,
    );
    await _audioPlayer.play();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (_audioPlayer.position > Duration.zero) {
      SourceLogBus.instance.emit(
          sourceId, SourceLogLevel.info, '播放器', '重设音频源后已开始推进');
    } else {
      SourceLogBus.instance.emit(
          sourceId, SourceLogLevel.warn, '播放器', '首播仍无进度（底层未启动）');
    }
  }

  void _updateState(PlayerState state) {
    _currentState = state;
    _stateController.add(state);
  }

  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  @override
  PlayerState get currentState => _currentState;

  @override
  Stream<int> get positionStream => _positionController.stream;

  @override
  int get currentPosition => _currentPosition;

  @override
  Stream<int> get durationStream => _durationController.stream;

  @override
  int get currentDuration => _currentDuration;

  @override
  PlayMode get playMode => _playMode;

  @override
  set playMode(PlayMode mode) {
    _playMode = mode;
    if (mode == PlayMode.shuffle) _shuffleHistory.clear();
    // 底层音源**永远不自己循环**：一首歌播完由 [_onTrackCompleted] 按 _playMode 决定下一首。
    //
    // 历史故障（用户报「设了列表循环却一直单曲循环」）：这里曾把 listLoop 映射成
    // LoopMode.all。但每首歌都是**单独一个 source**（setAudioSource 单曲），
    // LoopMode.all 就等于在这一首上无限重播，而且 just_audio 之后**不再上报 completed**
    // —— _onTrackCompleted 永远不触发，列表循环退化成单曲循环；
    // 上一曲/下一曲是显式调用，所以那两条路径看着正常，把问题掩盖了。
    _audioPlayer.setLoopMode(LoopMode.off);
  }

  @override
  Future<void> play(Song song) async {
    final existingIndex = _queue.indexWhere(
      (s) => s.id == song.id && s.sourceId == song.sourceId,
    );
    if (existingIndex >= 0) {
      // 用带播放地址的副本覆盖队列里的同一条（队列里可能只有 id 没有 url）
      _queue[existingIndex] = song;
      await jumpToIndex(existingIndex);
      return;
    }
    _queue.add(song);
    await _playIndex(_queue.length - 1);
  }

  @override
  Future<void> pause() async {
    await _audioPlayer.pause();
    _updateState(PlayerState.paused);
  }

  @override
  Future<void> resume() async {
    await _audioPlayer.play();
    _updateState(PlayerState.playing);
  }

  @override
  Future<void> stop() async {
    await _audioPlayer.stop();
    _updateState(PlayerState.stopped);
  }

  @override
  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _audioPlayer.setVolume(_volume);
  }

  @override
  double get volume => _volume;

  @override
  Future<void> next() async {
    if (_queue.isEmpty) return;
    if (_playMode == PlayMode.shuffle) {
      _playNextShuffle();
    } else {
      final nextIndex = (_currentIndex + 1) % _queue.length;
      await _playIndex(nextIndex);
    }
  }

  @override
  Future<void> previous() async {
    if (_queue.isEmpty) return;
    if (_playMode == PlayMode.shuffle && _shuffleHistory.isNotEmpty) {
      final prevIndex = _shuffleHistory.removeLast();
      await _playIndex(prevIndex);
    } else {
      final prevIndex = _currentIndex > 0 ? _currentIndex - 1 : _queue.length - 1;
      await _playIndex(prevIndex);
    }
  }

  @override
  void setQueue(List<Song> songs) {
    // 换队列**不代表停止播放**：本方法只改 Dart 侧列表，底层音源根本没动。
    // 旧实现把 _currentIndex 清成 -1 后立刻广播，于是"当前曲目"变成 null：
    // 播放条上的在播歌曲消失、而声音还在放（真机复现的异常态）。
    // 现在只重排队列，_audibleSong 保持不变，对外仍如实报在播的那一首。
    _queue = List.from(songs);
    _shuffleHistory.clear();
    _syncIndexToAudible();
    _emitCurrentSong();
  }

  /// 把索引对齐回"底层真正加载的那一首"（不在新队列里则为 -1）
  void _syncIndexToAudible() {
    final audible = _audibleSong;
    if (audible == null) {
      _currentIndex = -1;
      return;
    }
    final index = _queue
        .indexWhere((s) => s.globalKey == audible.globalKey);
    if (index != _currentIndex) _currentIndex = index;
  }

  @override
  List<Song> get queue => List.unmodifiable(_queue);

  @override
  int get currentIndex => _currentIndex;

  @override
  Song? get audibleSong => _audibleSong;

  @override
  Stream<Song?> get currentSongStream => _currentSongController.stream;

  void _emitCurrentSong() {
    if (!_currentSongController.isClosed) {
      _currentSongController.add(currentSong);
    }
  }

  @override
  Future<void> jumpToIndex(int index) async {
    await _playIndex(index);
  }

  @override
  Future<void> dispose() async {
    await _playerStateSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();

    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
    await _currentSongController.close();
    await _audioPlayer.dispose();
  }
}