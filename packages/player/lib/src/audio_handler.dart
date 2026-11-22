/// 后台播放侧车（audio_service 0.18.x）
///
/// 职责：把 [Player] 的「状态 / 当前曲目 / 队列 / 进度」同步到系统媒体面板
/// （Android 通知与锁屏、蓝牙/耳机元数据），并把系统发来的命令
/// （播放/暂停/上一个/下一个/进度跳转/点列表某首）转发回同一个 [Player]。
///
/// 为什么做「侧车」而不是「适配器 implements Player」：
/// [Player] 有 20+ 个成员，再包一层转发只会两处漂移；通知真正需要的只有
/// 「观察 + 转发命令」，所以这里独立成一个 [BaseAudioHandler] 子类，
/// PlayerImpl 一行不改（桌面端也不受任何影响）。
///
/// 只在 Android/iOS 启用；其他平台不初始化（audio_service 无桌面实现）。
library;

import 'dart:async';
import 'dart:ui' show Color;

import 'package:audio_service/audio_service.dart';
import 'package:core/core.dart';

/// 把本项目 [PlayerState] 映射为 audio_service 的处理状态
///
/// 单曲模式下不存在「正在缓冲」的独立状态：本项目把缓冲视为「仍在播/暂停」，
/// 因此 playing/paused 都映射到 ready（playing 由 [PlaybackState.playing] 表达）。
AudioProcessingState mapProcessingState(PlayerState state) => switch (state) {
      PlayerState.idle => AudioProcessingState.idle,
      PlayerState.loading => AudioProcessingState.loading,
      PlayerState.playing => AudioProcessingState.ready,
      PlayerState.paused => AudioProcessingState.ready,
      PlayerState.stopped => AudioProcessingState.idle,
      PlayerState.error => AudioProcessingState.error,
    };

/// 本项目播放模式 → 系统「循环模式」
///
/// shuffle 不参与循环语义（随机由 [mapShuffleMode] 单独表达）。
AudioServiceRepeatMode mapRepeatMode(PlayMode mode) => switch (mode) {
      PlayMode.listLoop => AudioServiceRepeatMode.all,
      PlayMode.singleLoop => AudioServiceRepeatMode.one,
      PlayMode.sequential => AudioServiceRepeatMode.none,
      PlayMode.shuffle => AudioServiceRepeatMode.none,
    };

/// 本项目播放模式 → 系统「随机模式」
AudioServiceShuffleMode mapShuffleMode(PlayMode mode) =>
    mode == PlayMode.shuffle
        ? AudioServiceShuffleMode.all
        : AudioServiceShuffleMode.none;

/// 通知/锁屏上按「playing」选出中间那颗按钮：上一首 / 播放或暂停 / 下一首
List<MediaControl> buildControls({required bool playing}) => <MediaControl>[
      MediaControl.custom(
        androidIcon: 'drawable/uiv2_shuffle',
        label: '随机',
        name: 'toggleShuffle',
      ),
      MediaControl.skipToPrevious,
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
      MediaControl.custom(
        androidIcon: 'drawable/uiv2_repeat',
        label: '循环',
        name: 'toggleRepeat',
      ),
    ];

/// [Song] → 系统媒体条目（id 用 globalKey，可反查队列/回源解析）
MediaItem songToMediaItem(Song song, {Duration? duration}) {
  final cover = song.coverUrl;
  final ms = song.duration;
  return MediaItem(
    id: song.globalKey,
    title: song.title,
    artist: song.artist,
    album: song.album,
    duration: duration ??
        (ms == null || ms <= 0 ? null : Duration(milliseconds: ms)),
    artUri: (cover == null || cover.trim().isEmpty)
        ? null
        : Uri.tryParse(cover.trim()),
  );
}

/// 后台播放 handler：观察 [Player] 并转发系统命令
class ResonanceAudioHandler extends BaseAudioHandler {
  /// 构造：立刻接管 [player] 的四条流（状态/进度/时长/当前曲目）
  ///
  /// [songResolver] 供「系统点播某首（Android Auto / 语音）」时按 globalKey
  /// 取到完整 [Song]；为 null 时用 [MediaItem] 自带字段兜底重建。
  ResonanceAudioHandler(
    this._player, {
    this.songResolver,
    Stream<Song?>? currentSongStream,
  }) {
    _subs.add(_player.stateStream.listen((_) {
      _emitPlaybackState();
      // 没有单独的「当前曲目流」时，靠状态变化兜底刷新曲目与队列
      if (currentSongStream == null) {
        _emitMediaItem();
        _emitQueue();
      }
    }));
    _subs.add(_player.positionStream.listen((ms) {
      // 只刷新进度：不动按钮集合，避免每 200ms 重建整份状态
      playbackState.add(playbackState.value
          .copyWith(updatePosition: Duration(milliseconds: ms)));
    }));
    _subs.add(_player.durationStream.listen((_) => _emitMediaItem()));
    if (currentSongStream != null) {
      _subs.add(currentSongStream.listen((_) {
        _emitQueue();
        _emitMediaItem();
        _emitPlaybackState();
      }));
    }
    _emitQueue();
    _emitMediaItem();
    _emitPlaybackState();
  }

  final Player _player;

  /// 系统点播时按 globalKey 反查完整 Song（可选）
  final Song? Function(String songKey)? songResolver;

  final List<StreamSubscription<dynamic>> _subs = <StreamSubscription<dynamic>>[];

  /// 上一次广播的队列快照（id 串），用于避免重复广播同一份队列
  String _lastQueueSignature = '';

  /// 车载歌词：第一行覆盖（null=不覆盖）
  String? _titleOverride;

  /// 车载歌词：第二行覆盖（null=不覆盖）
  String? _artistOverride;

  /// 设置/清除车载歌词覆盖（null 表示恢复真实歌名/歌手）
  ///
  /// 只影响系统媒体元数据（通知/车机），App 内 UI 仍用真实 Song。
  void setMetadataOverride({String? title, String? artist}) {
    if (_titleOverride == title && _artistOverride == artist) return;
    _titleOverride = title;
    _artistOverride = artist;
    _emitMediaItem();
  }

  /// 取消内部订阅（App 退出 / 测试收尾）
  Future<void> disposeHandler() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
  }

  // ==================== 自定义通知按钮 ====================

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'toggleShuffle':
        _player.playMode = _player.playMode == PlayMode.shuffle
            ? PlayMode.listLoop
            : PlayMode.shuffle;
      case 'toggleRepeat':
        _player.playMode = _player.playMode == PlayMode.singleLoop
            ? PlayMode.listLoop
            : PlayMode.singleLoop;
    }
    _emitPlaybackState();
  }

  // ==================== 对外命令（系统 -> Player） ====================

  @override
  Future<void> play() => _player.resume();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    // 系统可能不会回推状态（stop 后没有新事件），这里主动把面板置为停止态
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      processingState: AudioProcessingState.idle,
    ));
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.next();

  @override
  Future<void> skipToPrevious() => _player.previous();

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _player.queue.length) return;
    await _player.jumpToIndex(index);
  }

  @override
  Future<void> playMediaItem(MediaItem mediaItem) async {
    final song = _resolveSong(mediaItem);
    if (song != null) await _player.play(song);
  }

  @override
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {
    await playMediaItem(MediaItem(id: mediaId, title: ''));
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _player.playMode = switch (repeatMode) {
      AudioServiceRepeatMode.one => PlayMode.singleLoop,
      AudioServiceRepeatMode.all => PlayMode.listLoop,
      AudioServiceRepeatMode.group => PlayMode.listLoop,
      AudioServiceRepeatMode.none => PlayMode.sequential,
    };
    _emitPlaybackState();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _player.playMode = shuffleMode == AudioServiceShuffleMode.none
        ? PlayMode.listLoop
        : PlayMode.shuffle;
    _emitPlaybackState();
  }

  // ==================== 内部：Player -> 系统 ====================

  /// 广播完整播放状态（状态变化 / 换曲 / 模式变化时调用）
  void _emitPlaybackState() {
    final state = _player.currentState;
    final playing = state == PlayerState.playing;
    final index = _player.currentIndex;
    playbackState.add(PlaybackState(
      controls: buildControls(playing: playing),
      systemActions: const <MediaAction>{MediaAction.seek},
      androidCompactActionIndices: const <int>[0, 1, 2],
      processingState: mapProcessingState(state),
      playing: playing,
      updatePosition: Duration(milliseconds: _player.currentPosition),
      bufferedPosition: Duration(milliseconds: _player.currentPosition),
      repeatMode: mapRepeatMode(_player.playMode),
      shuffleMode: mapShuffleMode(_player.playMode),
      queueIndex: index >= 0 ? index : null,
    ));
  }

  /// 广播当前曲目（内容没变就不重复发，避免每 200ms 打一次平台通道）
  void _emitMediaItem() {
    final song = _player.currentSong;
    if (song == null) return;
    final duration = Duration(milliseconds: _player.currentDuration);
    final base = songToMediaItem(
      song,
      duration: duration > Duration.zero ? duration : null,
    );
    final next = (_titleOverride == null && _artistOverride == null)
        ? base
        : base.copyWith(
            title: _titleOverride ?? base.title,
            artist: _artistOverride ?? base.artist,
          );
    final prev = mediaItem.value;
    if (prev != null &&
        prev.id == next.id &&
        prev.title == next.title &&
        prev.artist == next.artist &&
        prev.album == next.album &&
        prev.duration == next.duration &&
        prev.artUri == next.artUri) {
      return;
    }
    mediaItem.add(next);
  }

  /// 广播队列（供 Android Auto / 通知的「上一首/下一首」可用性判断）
  void _emitQueue() {
    final songs = _player.queue;
    final signature = songs.map((s) => s.globalKey).join('|');
    if (signature == _lastQueueSignature) return;
    _lastQueueSignature = signature;
    queue.add(<MediaItem>[for (final song in songs) songToMediaItem(song)]);
  }

  /// 系统点播的 MediaItem -> Song
  ///
  /// 优先在队列里按 globalKey 找；找不到再问注入的 resolver；最后用
  /// MediaItem 自带字段重建（标题/歌手/时长/封面都在里面，够播放与展示）。
  Song? _resolveSong(MediaItem item) {
    for (final song in _player.queue) {
      if (song.globalKey == item.id) return song;
    }
    final resolved = songResolver?.call(item.id);
    if (resolved != null) return resolved;
    final parts = item.id.split(':');
    if (parts.length != 2) return null;
    return Song(
      id: parts[1],
      sourceId: parts[0],
      title: item.title,
      artist: item.artist ?? '',
      album: item.album,
      duration: item.duration?.inMilliseconds,
      coverUrl: item.artUri?.toString(),
    );
  }
}

/// 后台播放启动入口（仅 Android/iOS 调用）
///
/// 桌面端不要调用：audio_service 没有 Windows/Linux 实现。
abstract final class AudioBackground {
  /// 通知渠道与外观的默认配置（品牌红、常驻通知、暂停后退出前台）
  static const AudioServiceConfig defaultConfig = AudioServiceConfig(
    androidNotificationChannelId: 'com.resonance.app.channel.audio',
    androidNotificationChannelName: '回响播放',
    androidNotificationChannelDescription: '正在播放的歌曲与播放控制',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
    preloadArtwork: true,
    notificationColor: Color(0xFFC9341C),
    androidNotificationIcon: 'drawable/ic_stat_resonance',
  );

  /// 初始化系统媒体服务，返回挂到 [player] 上的 handler
  ///
  /// 必须在 WidgetsFlutterBinding.ensureInitialized() 之后、runApp 之前调用。
  static Future<ResonanceAudioHandler> init(
    Player player, {
    AudioServiceConfig? config,
    Song? Function(String songKey)? songResolver,
    Stream<Song?>? currentSongStream,
  }) {
    // PlayerImpl 实现 CurrentSongSource（换曲即广播）；其它实现没有这条流就退回
    // 「状态变化时刷新」，行为等价只是刷新粒度粗一点。
    // Player 与 CurrentSongSource 是两棵无关的接口树，Dart 不能自动提升类型，
    // 因此显式判断 + 显式转换（与 core 里 PlayerCurrentSong 的做法一致）。
    final songStream = currentSongStream ??
        (player is CurrentSongSource
            ? (player as CurrentSongSource).currentSongStream
            : null);
    return AudioService.init<ResonanceAudioHandler>(
      builder: () => ResonanceAudioHandler(
        player,
        songResolver: songResolver,
        currentSongStream: songStream,
      ),
      config: config ?? defaultConfig,
    );
  }
}
