import 'dart:async';

import 'package:core/core.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;

/// 基于 just_audio 的播放器实现
class PlayerImpl implements Player, CurrentSongSource {
  final AudioPlayer _audioPlayer = AudioPlayer();

  /// 队列里的曲目常常只有 id（来自最近播放/歌单快照，没有 playUrl）。
  /// 真正播放前用它现取一次地址；取到后写回队列，避免重复请求。
  final Future<String> Function(Song song)? urlResolver;

  List<Song> _queue = [];
  int _currentIndex = -1;
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

  Future<void> _doPlayIndex(int index, int token) async {
    if (index < 0 || index >= _queue.length) return;
    _loading = true;
    final previousIndex = _currentIndex;
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
    try {
      await _audioPlayer.setAudioSource(
          AudioSource.uri(Uri.parse(url)),
          preload: true);
      // 加载期间如果又来了新的播放请求，就不要再提交这一条（否则 UI 会停在过期的曲目）
      if (token != _playToken) return;
      // 关键：音频源真的被播放器接受之后才广播。
      // 之前在改 _currentIndex 时就广播，一旦加载失败/超时，UI 已是新歌、
      // 实际还在放上一首 —— 这正是"页面显示 A、实际播 B"的成因。
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

      await _audioPlayer.play();
      SourceLogBus.instance.emit(
        song.sourceId, SourceLogLevel.info, '播放器',
        'play() 完成（${sw.elapsedMilliseconds}ms），状态=${_currentState.name}');
      _updateState(PlayerState.playing);
    } catch (e, st) {
      SourceLogBus.instance.emit(
        song.sourceId, SourceLogLevel.error, '播放器',
        '播放失败 idx=$index id=${song.id} url=$url: $e\n$st');
      // 回滚：音频没切成功，索引退回，UI 跟着退回真正在播的那一首。
      // 只有仍是"当前请求"时才回滚，避免覆盖后来者的状态。
      if (token == _playToken) {
        _currentIndex = previousIndex;
        _emitCurrentSong();
      }
      _updateState(PlayerState.error);
    } finally {
      // 无论成功失败都要解除"加载中"，否则完成事件闸门会一直关着
      _loading = false;
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
    switch (mode) {
      case PlayMode.listLoop:
        _audioPlayer.setLoopMode(LoopMode.all);
      case PlayMode.singleLoop:
        _audioPlayer.setLoopMode(LoopMode.one);
      case PlayMode.shuffle:
        _audioPlayer.setLoopMode(LoopMode.off);
        _shuffleHistory.clear();
      case PlayMode.sequential:
        _audioPlayer.setLoopMode(LoopMode.off);
    }
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
    _queue = List.from(songs);
    _shuffleHistory.clear();
    _currentIndex = -1;
    _emitCurrentSong();
  }

  @override
  List<Song> get queue => List.unmodifiable(_queue);

  @override
  int get currentIndex => _currentIndex;

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