/// Riverpod Providers —— 全局服务与状态管理
///
/// 服务类 Provider 在 fm_app 的 main() 中通过 ProviderScope.overrides 注入。
/// 状态类 Provider 由 UI 层直接使用。

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

// ==================== 播放状态 ====================

/// 当前播放歌曲
final currentSongProvider = StateProvider<Song?>((ref) => null);

/// 播放队列
final playQueueProvider = StateProvider<List<Song>>((ref) => []);

/// 是否正在播放
final isPlayingProvider = StateProvider<bool>((ref) => false);

/// 当前播放进度（秒）
final positionProvider = StateProvider<Duration>((ref) => Duration.zero);

/// 总时长
final durationProvider = StateProvider<Duration>((ref) => Duration.zero);

/// 播放模式
final playModeProvider = StateProvider<PlayMode>((ref) => PlayMode.listLoop);

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
final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref.watch(settingsDaoProvider));
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final SettingsDao _settingsDao;

  ThemeModeNotifier(this._settingsDao) : super(ThemeMode.system) {
    _load();
  }

  /// 从数据库加载主题模式
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
final searchNotifierProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier(ref.watch(sourceManagerProvider));
});

class SearchNotifier extends StateNotifier<SearchState> {
  final SourceManager _sourceManager;

  SearchNotifier(this._sourceManager) : super(const SearchState());

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
    StateNotifierProvider<RecentPlaysNotifier, List<Song>>((ref) {
  return RecentPlaysNotifier(
    ref.watch(recentPlaysServiceProvider),
    ref.watch(sourceManagerProvider),
  );
});

class RecentPlaysNotifier extends StateNotifier<List<Song>> {
  final RecentPlaysService _service;
  final SourceManager _sourceManager;

  RecentPlaysNotifier(this._service, this._sourceManager) : super(const []);

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
final favoritesNotifierProvider =
    StateNotifierProvider<FavoritesNotifier, List<Song>>((ref) {
  return FavoritesNotifier(
    ref.watch(favoritesDaoProvider),
    ref.watch(sourceManagerProvider),
  );
});

class FavoritesNotifier extends StateNotifier<List<Song>> {
  final FavoritesDao _dao;
  final SourceManager _sourceManager;

  FavoritesNotifier(this._dao, this._sourceManager) : super(const []);

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
      await _dao.addFavorite(song.globalKey, DateTime.now().millisecondsSinceEpoch);
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
    StateNotifierProvider<SourceEnabledNotifier, Map<String, bool>>((ref) {
  return SourceEnabledNotifier(ref.watch(sourceManagerProvider));
});

class SourceEnabledNotifier extends StateNotifier<Map<String, bool>> {
  final SourceManager _manager;

  SourceEnabledNotifier(this._manager) : super({}) {
    _load();
  }

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
