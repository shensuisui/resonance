/// Riverpod Providers —— 全局服务与状态管理（v3 代码生成风格）
///
/// 服务类 Provider 在 fm_app 的 main() 中通过 ProviderScope.overrides 注入。
/// 状态类 Provider 由 UI 层直接使用。
///
/// 注意：代码生成默认 autoDispose，本文件所有 Provider 均为应用级生命周期，
/// 统一标注 keepAlive: true。

import 'dart:async';
import 'dart:convert';

import 'package:crawler/crawler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:core/core.dart';

export 'subscription_library.dart';

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

/// 歌曲是否已收藏
@Riverpod(keepAlive: true)
Future<bool> isFavorite(Ref ref, String songKey) {
  return ref.watch(favoritesDaoProvider).isFavorite(songKey);
}

// ==================== 播放控制 ====================

/// 播放控制器 —— 统一播放入口
///
/// 取播放 URL → 播放 → 同步 UI 状态 → 记录最近播放。
/// 所有页面通过此入口播放，避免重复逻辑、保证队列状态一致。
@Riverpod(keepAlive: true)
class PlaybackController extends _$PlaybackController {
  @override
  void build() {}

  SourceManager get _sourceManager => ref.read(sourceManagerProvider);
  Player get _player => ref.read(playerProvider);

  /// 播放一首歌（自动解析播放地址）
  Future<void> playSong(Song song) async {
    try {
      final url = await _sourceManager.getSongUrl(song.sourceId, song.id);
      final playable = song.copyWith(playUrl: url);
      await _player.play(playable);
      ref.read(currentSongProvider.notifier).setSong(playable);
      ref.read(isPlayingProvider.notifier).setPlaying(true);
      ref.read(playQueueProvider.notifier).setQueue(_player.queue);
      // 异步记录最近播放，不阻塞播放
      unawaited(ref.read(recentPlaysProvider.notifier).recordPlay(song));
    } catch (_) {
      ref.read(isPlayingProvider.notifier).setPlaying(false);
    }
  }

  /// 跳转到队列指定曲目并播放
  Future<void> jumpTo(int index) async {
    await _player.jumpToIndex(index);
    final queue = _player.queue;
    if (index >= 0 && index < queue.length) {
      ref.read(currentSongProvider.notifier).setSong(queue[index]);
      ref.read(isPlayingProvider.notifier).setPlaying(true);
    }
  }
}

/// 播放器状态流绑定 —— 底层播放器流同步到 UI 状态 Provider
///
/// 在 AppShell 中 watch 一次即可保持应用生命周期内生效：
/// 进度条、歌词同步、播放/暂停按钮状态都依赖此绑定。
@Riverpod(keepAlive: true)
void playerStreamBinding(Ref ref) {
  final player = ref.watch(playerProvider);
  final subs = <StreamSubscription<dynamic>>[];

  subs.add(player.stateStream.listen((s) {
    ref.read(isPlayingProvider.notifier).setPlaying(s == PlayerState.playing);
  }));
  subs.add(player.positionStream.listen((ms) {
    ref
        .read(playbackPositionProvider.notifier)
        .setPosition(Duration(milliseconds: ms));
  }));
  subs.add(player.durationStream.listen((ms) {
    ref
        .read(playbackDurationProvider.notifier)
        .setDuration(Duration(milliseconds: ms));
  }));

  ref.onDispose(() {
    for (final sub in subs) {
      sub.cancel();
    }
  });
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

/// 搜索结果的单个来源分组
class SearchGroup {
  final String sourceId;
  final String sourceName;
  final List<Song> songs;

  const SearchGroup({
    required this.sourceId,
    required this.sourceName,
    required this.songs,
  });
}

/// 搜索状态
class SearchState {
  final String keyword;

  /// 全部来源聚合结果（「全部」tab）
  final List<Song> allResults;

  /// 按来源分组（每个来源一个 tab）
  final List<SearchGroup> groups;
  final bool loading;
  final bool hasMore;

  const SearchState({
    this.keyword = '',
    this.allResults = const [],
    this.groups = const [],
    this.loading = false,
    this.hasMore = false,
  });

  SearchState copyWith({
    String? keyword,
    List<Song>? allResults,
    List<SearchGroup>? groups,
    bool? loading,
    bool? hasMore,
  }) {
    return SearchState(
      keyword: keyword ?? this.keyword,
      allResults: allResults ?? this.allResults,
      groups: groups ?? this.groups,
      loading: loading ?? this.loading,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

/// 搜索历史（持久化，新→旧，去重移顶，上限 [SearchHistory._maxEntries]）
@Riverpod(keepAlive: true)
class SearchHistory extends _$SearchHistory {
  static const int _maxEntries = 20;
  static const String _key = 'search_history';

  @override
  List<String> build() {
    load();
    return const [];
  }

  SettingsDao get _settingsDao => ref.read(settingsDaoProvider);

  Future<void> load() async {
    try {
      final raw = await _settingsDao.get(_key);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List<dynamic>).cast<String>();
      state = list;
    } catch (_) {
      state = const [];
    }
  }

  /// 记录一次搜索：去重移顶 + 上限截断 + 持久化
  Future<void> add(String keyword) async {
    final k = keyword.trim();
    if (k.isEmpty) return;
    final updated = [k, ...state.where((e) => e != k)];
    final capped = updated.take(_maxEntries).toList();
    state = capped;
    await _settingsDao.set(_key, jsonEncode(capped));
  }

  Future<void> remove(String keyword) async {
    final updated = state.where((e) => e != keyword).toList();
    state = updated;
    await _settingsDao.set(_key, jsonEncode(updated));
  }

  Future<void> clear() async {
    state = const [];
    await _settingsDao.set(_key, '[]');
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
    // 记录搜索历史（去重移顶 + 上限）
    ref.read(searchHistoryProvider.notifier).add(keyword);
    state = SearchState(keyword: keyword, loading: true);
    try {
      final results = await _sourceManager.searchAll(keyword: keyword);
      final groups = <SearchGroup>[];
      final all = <Song>[];
      for (final r in results) {
        if (r.songs.isEmpty) continue;
        final name = _sourceManager.getSource(r.sourceId)?.sourceInfo.name ??
            r.sourceId;
        groups.add(SearchGroup(
          sourceId: r.sourceId,
          sourceName: name,
          songs: r.songs,
        ));
        all.addAll(r.songs);
      }
      state = SearchState(
        keyword: keyword,
        allResults: all,
        groups: groups,
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

// ==================== 源执行日志 ====================

/// 源执行日志状态
class SourceLogState {
  final List<SourceLogEntry> entries;
  const SourceLogState({this.entries = const []});
}

/// 源执行日志 Notifier —— 订阅 SourceLogBus，保留最近 200 条
@Riverpod(keepAlive: true)
class SourceLog extends _$SourceLog {
  static const int _maxEntries = 200;

  @override
  SourceLogState build() {
    // 先取历史，再订阅实时流
    final initial = SourceLogBus.instance.entries.take(_maxEntries).toList();
    _sub = SourceLogBus.instance.stream.listen((e) {
      state = SourceLogState(
        entries: [e, ...state.entries.take(_maxEntries - 1)],
      );
    });
    ref.onDispose(() => _sub?.cancel());
    return SourceLogState(entries: initial);
  }

  StreamSubscription<SourceLogEntry>? _sub;

  /// 清空日志
  void clear() {
    SourceLogBus.instance.clear();
    state = const SourceLogState();
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

// ==================== 插件管理 ====================

/// 插件库状态
class PluginLibraryState {
  /// 已加载的插件源
  final List<MusicSource> plugins;
  final bool loading;

  /// 最近一次操作结果提示（成功/失败原因）
  final String? message;

  const PluginLibraryState({
    this.plugins = const [],
    this.loading = false,
    this.message,
  });
}

/// 插件库 Notifier —— 插件的加载/导入/下载与持久化
///
/// 插件文件统一存放在应用支持目录的 plugins/ 子目录，
/// 启动时自动加载（AppShell watch 触发），支持：
/// - 本地目录批量加载
/// - 从 URL 下载
/// - 从文件导入
/// - 加载 PRD 默认远程插件源（落雪 / MusicFree）
@Riverpod(keepAlive: true)
class PluginLibrary extends _$PluginLibrary {
  @override
  PluginLibraryState build() {
    loadLocal();
    return const PluginLibraryState(loading: true);
  }

  SourceManager get _sourceManager => ref.read(sourceManagerProvider);

  /// 插件持久化目录（应用支持目录/plugins）
  Future<String> get _pluginDir async {
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'plugins');
  }

  /// 启动加载：扫描本地插件目录并注册为音乐源
  Future<void> loadLocal() async {
    try {
      final dir = await _pluginDir;
      final sources = await PluginManager.loadPluginsFromDirectory(dir);
      for (final source in sources) {
        _sourceManager.registerSource(source);
      }
      if (sources.isNotEmpty) {
        ref.invalidate(sourceListProvider);
      }
      state = PluginLibraryState(plugins: sources);
    } catch (e) {
      // Web 等无文件系统平台静默降级
      state = PluginLibraryState(message: '本地插件加载失败: $e');
    }
  }

  /// 从本地文件导入插件（文件选择器）
  Future<bool> importFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['js', 'json', 'lx', 'mf', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return false;
    final file = result.files.single;

    // 内容获取：Web 用 bytes，原生用 file_service 读路径
    String content;
    if (file.bytes != null) {
      content = utf8.decode(file.bytes!);
    } else if (file.path != null) {
      content = await readFileAsString(file.path!);
    } else {
      state = _withMessage('无法读取所选文件');
      return false;
    }

    // 复制进插件目录持久化，再解析注册
    final dir = await _pluginDir;
    final dest = p.join(dir, file.name);
    await writeFileAsString(dest, content);
    return await _registerFile(dest);
  }

  /// 解析插件文件并注册为音乐源
  Future<bool> _registerFile(String filePath) async {
    final source = await PluginManager.loadPlugin(filePath);
    if (source == null) {
      state = _withMessage('插件解析失败：$filePath');
      return false;
    }
    _sourceManager.registerSource(source);
    ref.invalidate(sourceListProvider);
    state = PluginLibraryState(
      plugins: [...state.plugins, source],
      message: '已加载插件：${source.sourceInfo.name}',
    );
    return true;
  }

  PluginLibraryState _withMessage(String msg) =>
      PluginLibraryState(plugins: state.plugins, message: msg);
}
