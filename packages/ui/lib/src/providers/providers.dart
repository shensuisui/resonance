/// Riverpod Providers —— 全局服务与状态管理
///
/// 服务类 Provider 在 fm_app 的 main() 中通过 ProviderScope.overrides 注入。
/// 状态类 Provider 由 UI 层直接使用（Riverpod 3.x Notifier 风格）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';

// ==================== 服务 Provider（fm_app override） ====================

/// 数据库提供者
final databaseProvider = Provider<DatabaseProvider>((ref) {
  throw UnimplementedError('databaseProvider must be overridden');
});

/// 源管理器
final sourceManagerProvider = Provider<SourceManager>((ref) {
  throw UnimplementedError('sourceManagerProvider must be overridden');
});

/// 最近播放服务
final recentPlaysServiceProvider = Provider<RecentPlaysService>((ref) {
  throw UnimplementedError('recentPlaysServiceProvider must be overridden');
});

/// 播放器接口（fm_app override 为 PlayerImpl）
final playerProvider = Provider<Player>((ref) {
  throw UnimplementedError('playerProvider must be overridden');
});

/// 下载管理器（fm_app override 为 DownloadManagerImpl）
final downloadManagerProvider = Provider<DownloadManager>((ref) {
  throw UnimplementedError('downloadManagerProvider must be overridden');
});

/// 下载任务列表（监听 taskStream 实时更新）
final downloadTasksProvider = StreamProvider<List<DownloadTask>>((ref) {
  final manager = ref.watch(downloadManagerProvider);
  return manager.taskStream;
});

// ==================== 播放状态 ====================

/// 当前播放歌曲
final currentSongProvider = NotifierProvider<CurrentSongNotifier, Song?>(
    CurrentSongNotifier.new);

class CurrentSongNotifier extends Notifier<Song?> {
  @override
  Song? build() => null;

  void setSong(Song? song) => state = song;
}

/// 播放队列
final playQueueProvider = NotifierProvider<PlayQueueNotifier, List<Song>>(
    PlayQueueNotifier.new);

class PlayQueueNotifier extends Notifier<List<Song>> {
  @override
  List<Song> build() => const [];

  void setQueue(List<Song> queue) => state = List.from(queue);
}

/// 是否正在播放
final isPlayingProvider = NotifierProvider<IsPlayingNotifier, bool>(
    IsPlayingNotifier.new);

class IsPlayingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setPlaying(bool playing) => state = playing;
}

/// 当前播放进度
final positionProvider = NotifierProvider<PositionNotifier, Duration>(
    PositionNotifier.new);

class PositionNotifier extends Notifier<Duration> {
  @override
  Duration build() => Duration.zero;

  void setPosition(Duration position) => state = position;
}

/// 总时长
final durationProvider = NotifierProvider<DurationNotifier, Duration>(
    DurationNotifier.new);

class DurationNotifier extends Notifier<Duration> {
  @override
  Duration build() => Duration.zero;

  void setDuration(Duration duration) => state = duration;
}

/// 播放模式（持久化）
final playModeProvider = NotifierProvider<PlayModeNotifier, PlayMode>(
    PlayModeNotifier.new);

class PlayModeNotifier extends Notifier<PlayMode> {
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

// ==================== 便捷 DAO Provider ====================

final songDaoProvider = Provider<SongDao>((ref) {
  return ref.watch(databaseProvider).songDao;
});

final settingsDaoProvider = Provider<SettingsDao>((ref) {
  return ref.watch(databaseProvider).settingsDao;
});

final playlistDaoProvider = Provider<PlaylistDao>((ref) {
  return ref.watch(databaseProvider).playlistDao;
});

final favoritesDaoProvider = Provider<FavoritesDao>((ref) {
  return ref.watch(databaseProvider).favoritesDao;
});

// ==================== 主题模式 ====================

/// 主题模式状态
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
    ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
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
final searchNotifierProvider = NotifierProvider<SearchNotifier, SearchState>(
    SearchNotifier.new);

class SearchNotifier extends Notifier<SearchState> {
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
final recentPlaysNotifierProvider =
    NotifierProvider<RecentPlaysNotifier, List<Song>>(RecentPlaysNotifier.new);

class RecentPlaysNotifier extends Notifier<List<Song>> {
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
final favoritesNotifierProvider = NotifierProvider<FavoritesNotifier, List<Song>>(
    FavoritesNotifier.new);

class FavoritesNotifier extends Notifier<List<Song>> {
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
final sourceListProvider = FutureProvider<List<MusicSource>>((ref) async {
  final manager = ref.watch(sourceManagerProvider);
  return manager.getAllSources();
});

/// 源启用状态
final sourceEnabledProvider =
    NotifierProvider<SourceEnabledNotifier, Map<String, bool>>(
        SourceEnabledNotifier.new);

class SourceEnabledNotifier extends Notifier<Map<String, bool>> {
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
final scanNotifierProvider = NotifierProvider<ScanNotifier, ScanState>(
    ScanNotifier.new);

class ScanNotifier extends Notifier<ScanState> {
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
