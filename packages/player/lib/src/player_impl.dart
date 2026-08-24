import 'dart:async';

import 'package:core/core.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;

/// 基于 just_audio 的播放器实现
class PlayerImpl implements Player {
  final AudioPlayer _audioPlayer = AudioPlayer();

  List<Song> _queue = [];
  int _currentIndex = -1;
  PlayMode _playMode = PlayMode.listLoop;
  final List<int> _shuffleHistory = [];

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
  StreamSubscription? _playerCompleteSub;

  PlayerImpl() {
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

    _playerCompleteSub = _audioPlayer.processingStateStream
        .where((state) => state == ProcessingState.completed)
        .listen((_) => _onTrackCompleted());
  }

  void _onTrackCompleted() {
    if (_queue.isEmpty) return;

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

  Future<void> _playIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    final song = _queue[index];
    _updateState(PlayerState.loading);
    try {
      await _audioPlayer.setAudioSource(AudioSource.uri(Uri.parse(song.playUrl ?? '')));
      await _audioPlayer.play();
      _updateState(PlayerState.playing);
    } catch (e) {
      _updateState(PlayerState.error);
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
  }

  @override
  List<Song> get queue => List.unmodifiable(_queue);

  @override
  int get currentIndex => _currentIndex;

  @override
  Future<void> jumpToIndex(int index) async {
    await _playIndex(index);
  }

  @override
  Future<void> dispose() async {
    await _playerStateSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _playerCompleteSub?.cancel();
    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
    await _audioPlayer.dispose();
  }
}