/// Riverpod Providers —— 全局服务与状态管理（v3 代码生成风格）
///
/// 服务类 Provider 在 fm_app 的 main() 中通过 ProviderScope.overrides 注入。
/// 状态类 Provider 由 UI 层直接使用。
///
/// 注意：代码生成默认 autoDispose，本文件所有 Provider 均为应用级生命周期，
/// 统一标注 keepAlive: true。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:core/core.dart';

part 'providers.g.dart';

// ==================== 服务 Provider（fm_app override） ====================

/// 数据库提供者
///
/// 函数名避开 `database`：生成类名会是 DatabaseProvider，与 core 同名抽象类冲突。
@Riverpod(keepAlive: true)
DatabaseProvider appDatabase(Ref ref) =>
    throw UnimplementedError('appDatabaseProvider must be overridden');

/// 源管理器
@Riverpod(keepAlive: true)
SourceManager sourceManager(Ref ref) =>
    throw UnimplementedError('sourceManagerProvider must be overridden');

/// 最近播放服务
@Riverpod(keepAlive: true)
RecentPlaysService recentPlaysService(Ref ref) =>
    throw UnimplementedError('recentPlaysServiceProvider must be overridden');

/// 播放器接口（fm_app override 为 PlayerImpl）
@Riverpod(keepAlive: true)
Player player(Ref ref) =>
    throw UnimplementedError('playerProvider must be overridden');

/// 下载管理器（fm_app override 为 DownloadManagerImpl）
@Riverpod(keepAlive: true)
DownloadManager downloadManager(Ref ref) =>
    throw UnimplementedError('downloadManagerProvider must be overridden');

// ==================== 便捷 DAO Provider ====================

@Riverpod(keepAlive: true)
SongDao songDao(Ref ref) => ref.watch(appDatabaseProvider).songDao;

@Riverpod(keepAlive: true)
SettingsDao settingsDao(Ref ref) => ref.watch(appDatabaseProvider).settingsDao;

@Riverpod(keepAlive: true)
PlaylistDao playlistDao(Ref ref) => ref.watch(appDatabaseProvider).playlistDao;

@Riverpod(keepAlive: true)
FavoritesDao favoritesDao(Ref ref) =>
    ref.watch(appDatabaseProvider).favoritesDao;

/// 下载任务流（来自 DownloadManager）
@Riverpod(keepAlive: true)
Stream<List<DownloadTask>> downloadTasks(Ref ref) {
  return ref.watch(downloadManagerProvider).taskStream;
}

// ==================== 播放状态 ====================

/// 当前播放歌曲
@Riverpod(keepAlive: true)
class CurrentSong extends _$CurrentSong {
  @override
  Song? build() => null;

  void setSong(Song? song) => state = song;
}

/// 播放队列
@Riverpod(keepAlive: true)
class PlayQueue extends _$PlayQueue {
  @override
  List<Song> build() => const [];

  void setQueue(List<Song> queue) => state = List.from(queue);
}

/// 是否正在播放
@Riverpod(keepAlive: true)
class IsPlaying extends _$IsPlaying {
  @override
  bool build() => false;

  void setPlaying(bool playing) => state = playing;
}

/// 当前播放进度
@Riverpod(keepAlive: true)
class PlaybackPosition extends _$PlaybackPosition {
  @override
  Duration build() => Duration.zero;

  void setPosition(Duration position) => state = position;
}

/// 总时长
@Riverpod(keepAlive: true)
class PlaybackDuration extends _$PlaybackDuration {
  @override
  Duration build() => Duration.zero;

  void setDuration(Duration duration) => state = duration;
}

/// 播放模式（持久化）
@Riverpod(keepAlive: true)
class PlayModeNotifier extends _$PlayModeNotifier {
  @override
  PlayMode build() {
    _load();
    return PlayMode.listLoop;
  }

  SettingsDao get _settingsDao => ref.read(settingsDaoProvider);
  Player get _player => ref.read(playerProvider);

  Future<void> _load() async {
    final mode = await _settingsDao.get('play_mode');
    switch (mode) {
      case 'single':
        state = PlayMode.singleLoop;
        _player.playMode = PlayMode.singleLoop;
        break;
      case 'shuffle':
        state = PlayMode.shuffle;
        _player.playMode = PlayMode.shuffle;
        break;
      case 'sequential':
        state = PlayMode.sequential;
        _player.playMode = PlayMode.sequential;
        break;
      default:
        state = PlayMode.listLoop;
        _player.playMode = PlayMode.listLoop;
    }
  }

  Future<void> setMode(PlayMode mode) async {
    state = mode;
    _player.playMode = mode;
    final value = switch (mode) {
      PlayMode.singleLoop => 'single',
      PlayMode.shuffle => 'shuffle',
      PlayMode.sequential => 'sequential',
      PlayMode.listLoop => 'list',
    };
    await _settingsDao.set('play_mode', value);
  }
}

// ==================== 主题模式 ====================

/// 主题模式状态
@Riverpod(keepAlive: true)
class ThemeModeNotifier extends _$ThemeModeNotifier {
  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  SettingsDao get _settingsDao => ref.read(settingsDaoProvider);

  Future<void> _load() async {
    final mode = await _settingsDao.get('theme_mode');
    switch (mode) {
      case 'light':
        state = ThemeMode.light;
        break;
      case 'dark':
        state = ThemeMode.dark;
        break;
      default:
        state = ThemeMode.system;
    }
  }

  /// 切换主题模式并持久化
  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await _settingsDao.set('theme_mode', value);
  }
}

// ==================== 搜索状态 ====================

/// 搜索状态
class SearchState {
  final String keyword;
  final List<Song> results;
  final bool loading;
  final bool hasMore;

  const SearchState({
    this.keyword = '',
    this.results = const [],
    this.loading = false,
    this.hasMore = false,
  });

  SearchState copyWith({
    String? keyword,
    List<Song>? results,
    bool? loading,
    bool? hasMore,
  }) {
    return SearchState(
      keyword: keyword ?? this.keyword,
      results: results ?? this.results,
      loading: loading ?? this.loading,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

/// 搜索 Notifier
@Riverpod(keepAlive: true)
class SearchNotifier extends _$SearchNotifier {
  @override
  SearchState build() => const SearchState();

  SourceManager get _sourceManager => ref.read(sourceManagerProvider);

  /// 执行聚合搜索
  Future<void> search(String keyword) async {
    state = SearchState(keyword: keyword, loading: true);
    try {
      final results = await _sourceManager.searchAll(keyword: keyword);
      final songs = results.expand((r) => r.songs).toList();
      state = SearchState(
        keyword: keyword,
        results: songs,
        loading: false,
        hasMore: results.any((r) => r.hasMore),
      );
    } catch (e) {
      state = SearchState(keyword: keyword, loading: false);
    }
  }

  /// 清空搜索
  void clear() {
    state = const SearchState();
  }
}

// ==================== 最近播放 ====================

/// 最近播放列表
@Riverpod(keepAlive: true)
class RecentPlaysNotifier extends _$RecentPlaysNotifier {
  @override
  List<Song> build() {
    load();
    return const [];
  }

  RecentPlaysService get _service => ref.read(recentPlaysServiceProvider);
  SourceManager get _sourceManager => ref.read(sourceManagerProvider);

  /// 加载最近播放列表
  Future<void> load() async {
    final keys = await _service.getRecentSongKeys();
    final songs = <Song>[];
    for (final key in keys) {
      final parts = key.split(':');
      if (parts.length != 2) continue;
      try {
        final song = await _sourceManager.getSongDetail(parts[0], parts[1]);
        songs.add(song);
      } catch (_) {
        // 源不可用时跳过
      }
    }
    state = songs;
  }

  /// 记录播放
  Future<void> recordPlay(Song song) async {
    await _service.recordPlay(song);
    await load();
  }
}

// ==================== 收藏 ====================

/// 收藏列表
@Riverpod(keepAlive: true)
class FavoritesNotifier extends _$FavoritesNotifier {
  @override
  List<Song> build() {
    load();
    return const [];
  }

  FavoritesDao get _dao => ref.read(favoritesDaoProvider);
  SourceManager get _sourceManager => ref.read(sourceManagerProvider);

  Future<void> load() async {
    final keys = await _dao.getAllFavoriteKeys();
    final songs = <Song>[];
    for (final key in keys) {
      final parts = key.split(':');
      if (parts.length != 2) continue;
      try {
        final song = await _sourceManager.getSongDetail(parts[0], parts[1]);
        songs.add(song);
      } catch (_) {}
    }
    state = songs;
  }

  Future<void> toggle(Song song) async {
    final isFav = await _dao.isFavorite(song.globalKey);
    if (isFav) {
      await _dao.removeFavorite(song.globalKey);
    } else {
      await _dao.addFavorite(
          song.globalKey, DateTime.now().millisecondsSinceEpoch);
    }
    await load();
  }

  Future<bool> isFavorite(String songKey) {
    return _dao.isFavorite(songKey);
  }
}

// ==================== 源列表 ====================

/// 已注册源列表
@Riverpod(keepAlive: true)
Future<List<MusicSource>> sourceList(Ref ref) async {
  final manager = ref.watch(sourceManagerProvider);
  return manager.getAllSources();
}

/// 源启用状态
@Riverpod(keepAlive: true)
class SourceEnabled extends _$SourceEnabled {
  @override
  Map<String, bool> build() {
    _load();
    return const {};
  }

  SourceManager get _manager => ref.read(sourceManagerProvider);

  void _load() {
    final sources = _manager.getAllSources();
    final map = <String, bool>{};
    for (final s in sources) {
      map[s.sourceInfo.id] = _manager.isSourceEnabled(s.sourceInfo.id);
    }
    state = map;
  }

  Future<void> toggle(String sourceId, bool enabled) async {
    _manager.setSourceEnabled(sourceId, enabled);
    state = {...state, sourceId: enabled};
  }
}

// ==================== 本地扫描 ====================

/// 扫描状态
class ScanState {
  final bool scanning;
  final int? foundCount;
  final String? error;

  const ScanState({this.scanning = false, this.foundCount, this.error});
}

/// 本地扫描 Notifier
@Riverpod(keepAlive: true)
class ScanNotifier extends _$ScanNotifier {
  @override
  ScanState build() => const ScanState();

  SourceManager get _sourceManager => ref.read(sourceManagerProvider);
  SettingsDao get _settingsDao => ref.read(settingsDaoProvider);

  /// 获取扫描目录
  Future<String?> getScanDir() => _settingsDao.get('scan_dir');

  /// 设置扫描目录
  Future<void> setScanDir(String path) async {
    await _settingsDao.set('scan_dir', path);
  }

  /// 执行扫描
  Future<void> scan() async {
    state = const ScanState(scanning: true);
    try {
      final source = _sourceManager.getSource('local_scan');
      if (source == null || source is! LocalScanSource) {
        state = const ScanState(error: '本地扫描源未注册');
        return;
      }
      final count = await source.scanFromConfig();
      state = ScanState(scanning: false, foundCount: count);
    } catch (e) {
      state = ScanState(scanning: false, error: e.toString());
    }
  }
}

// ==================== 发现页 ====================

/// 发现页状态
class DiscoverState {
  final List<Playlist> playlists;
  final bool loading;
  final String? error;

  const DiscoverState({
    this.playlists = const [],
    this.loading = false,
    this.error,
  });
}

/// 发现页 Notifier —— 聚合各源的推荐歌单
@Riverpod(keepAlive: true)
class DiscoverNotifier extends _$DiscoverNotifier {
  @override
  DiscoverState build() {
    load();
    return const DiscoverState(loading: true);
  }

  SourceManager get _sourceManager => ref.read(sourceManagerProvider);

  Future<void> load() async {
    state = const DiscoverState(loading: true);
    final all = <Playlist>[];
    try {
      for (final source in _sourceManager.getEnabledSources()) {
        try {
          final playlists = await source.getPlaylistList();
          all.addAll(playlists);
        } catch (_) {
          // 单源失败跳过，不影响其他源
        }
      }
      state = DiscoverState(playlists: all, loading: false);
    } catch (e) {
      state = DiscoverState(loading: false, error: e.toString());
    }
  }
}

// ==================== 歌词 ====================

/// 当前歌曲歌词（随 currentSong 变化自动加载）
@Riverpod(keepAlive: true)
class LyricsNotifier extends _$LyricsNotifier {
  @override
  Lyrics? build() {
    final song = ref.watch(currentSongProvider);
    if (song != null) {
      _load(song);
    }
    return null;
  }

  SourceManager get _sourceManager => ref.read(sourceManagerProvider);

  Future<void> _load(Song song) async {
    try {
      final lyrics = await _sourceManager.getLyrics(song.sourceId, song.id);
      // 避免歌曲已切换后旧歌词覆盖新歌词
      final current = ref.read(currentSongProvider);
      final sameSong = current != null &&
          current.sourceId == song.sourceId &&
          current.id == song.id;
      if (!sameSong) return;
      state = (lyrics != null && lyrics.lines.isNotEmpty) ? lyrics : null;
    } catch (_) {
      state = null;
    }
  }
}
