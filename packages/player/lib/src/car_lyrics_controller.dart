/// 车载歌词控制器：把“当前歌词行”按配置写进系统媒体元数据
///
/// 只依赖流与回调，不直接触碰平台，便于单测：
///   * 歌切换 → 重置并按需异步加载歌词；
///   * 播放位置 → 二分找当前行，**行变化才推送**；
///   * 暂停/停止 → 清除覆盖（恢复真实歌名）；
///   * 配置/蓝牙连接变化 → [refresh] 重算。
library;

import 'dart:async';

import 'package:core/core.dart';

/// 歌词加载器（按歌曲 key 取歌词）
typedef CarLyricsResolver = Future<Lyrics?> Function(String songKey);

/// 控制器
class CarLyricsController {
  /// 构造并立即订阅
  CarLyricsController({
    required Stream<Duration> positionStream,
    required Stream<Song?> songStream,
    required Stream<bool> playingStream,
    required CarLyricsResolver lyricsOf,
    required void Function(CarLyricsMetadata? metadata) onMetadata,
    required CarLyricsConfig Function() config,
    required bool Function() bluetoothConnected,
    required bool Function() carDetected,
  })  : _lyricsOf = lyricsOf,
        _onMetadata = onMetadata,
        _config = config,
        _bluetoothConnected = bluetoothConnected,
        _carDetected = carDetected {
    _subs.add(positionStream.listen(_onPosition));
    _subs.add(songStream.listen(_onSong));
    _subs.add(playingStream.listen(_onPlaying));
  }

  final CarLyricsResolver _lyricsOf;
  final void Function(CarLyricsMetadata? metadata) _onMetadata;
  final CarLyricsConfig Function() _config;
  final bool Function() _bluetoothConnected;
  final bool Function() _carDetected;

  final List<StreamSubscription<dynamic>> _subs = <StreamSubscription<dynamic>>[];

  Song? _song;
  Lyrics? _lines;
  Duration _position = Duration.zero;
  bool _playing = false;

  /// 上一次推送的歌词行下标（用于去重）
  int? _lastIndex;

  /// 上一次推送的覆盖（null=已恢复）
  CarLyricsMetadata? _lastMeta;

  /// 当前歌词行（测试/调试用）
  String? get currentLine {
    final idx = _lastIndex;
    final lines = _lines;
    if (idx == null || lines == null || idx < 0 || idx >= lines.lines.length) {
      return null;
    }
    return lines.lines[idx].text;
  }

  /// 配置/蓝牙/车机状态变化后重算
  void refresh() => _recompute();

  void _onSong(Song? song) {
    if (song?.globalKey == _song?.globalKey) return;
    _song = song;
    _lines = null;
    _lastIndex = null;
    _push(null); // 切歌先恢复真实歌名
    if (song == null) return;
    final key = song.globalKey;
    unawaited(_lyricsOf(key).then((lyrics) {
      if (_song?.globalKey != key) return; // 已切到别的歌
      _lines = lyrics;
      _recompute();
    }).catchError((Object _) {
      // 歌词取不到：保持不注入
    }));
  }

  void _onPosition(Duration pos) {
    _position = pos;
    _recompute();
  }

  void _onPlaying(bool playing) {
    _playing = playing;
    if (!playing) {
      _lastIndex = null;
      _push(null);
      return;
    }
    _recompute();
  }

  void _recompute() {
    if (!_playing) {
      _push(null);
      return;
    }
    final song = _song;
    final lyrics = _lines;
    if (song == null || lyrics == null || lyrics.lines.isEmpty) {
      _lastIndex = null;
      _push(null);
      return;
    }
    final idx = carLyricLineIndexAt(lyrics.lines, _position);
    _lastIndex = idx;
    // 去重交给 _push（比较最终元数据）：同一行不重复推送，
    // 但配置/蓝牙状态变化导致结果不同时会补推。
    final line = idx == null ? null : lyrics.lines[idx].text;
    _push(resolveCarLyricsMetadata(
      config: _config(),
      bluetoothConnected: _bluetoothConnected(),
      carDetected: _carDetected(),
      lyricLine: line,
      songTitle: song.title,
      songArtist: song.artist,
    ));
  }

  void _push(CarLyricsMetadata? meta) {
    if (meta == _lastMeta) return;
    _lastMeta = meta;
    _onMetadata(meta);
  }

  /// 取消订阅
  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
  }
}
