/// 状态层 —— 真实数据能力接线（显式 Riverpod Provider，不使用代码生成）。
///
/// 设计原则（对应「不要 mock，用项目已有能力」）：
///   * 服务类 Provider（appDatabase/sourceManager/player/downloadManager/
///     recentPlaysService）由壳工程在 ProviderScope.overrides 注入；
///   * 所有列表数据都来自真实来源：DAO（收藏/歌单/最近播放/设置）、
///     SourceManager（搜索/歌单/专辑/艺人/歌词）、LocalScanSource（本地曲目）、
///     DownloadManager（下载任务）、SourceLogBus（运行日志）；
///   * 原型的内置曲库被包装成**真实音乐源** `demo_catalog`（见 catalog_source.dart），
///     与其它源一样注册进 SourceManager，可启用/停用，不再有 mock 分支。
library;

import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalog.dart';
import '../data/catalog_source.dart';

// ==================== 壳工程注入的服务 ====================

/// 数据库提供者（壳工程 override）
final appDatabaseProvider = Provider<DatabaseProvider>(
  (ref) => throw UnimplementedError('appDatabaseProvider 必须被覆盖'),
  name: 'appDatabaseProvider',
);

/// 源管理器（壳工程 override）
final sourceManagerProvider = Provider<SourceManager>(
  (ref) => throw UnimplementedError('sourceManagerProvider 必须被覆盖'),
  name: 'sourceManagerProvider',
);

/// 播放器（壳工程 override 为 PlayerImpl）
final playerProvider = Provider<Player>(
  (ref) => throw UnimplementedError('playerProvider 必须被覆盖'),
  name: 'playerProvider',
);

/// 下载管理器（壳工程 override 为 DownloadManagerImpl）
final downloadManagerProvider = Provider<DownloadManager>(
  (ref) => throw UnimplementedError('downloadManagerProvider 必须被覆盖'),
  name: 'downloadManagerProvider',
);

/// 最近播放服务（壳工程 override）
final recentPlaysServiceProvider = Provider<RecentPlaysService>(
  (ref) => throw UnimplementedError('recentPlaysServiceProvider 必须被覆盖'),
  name: 'recentPlaysServiceProvider',
);

// ==================== 便捷 DAO ====================

/// 歌曲 DAO
final songDaoProvider = Provider<SongDao>(
  (ref) => ref.watch(appDatabaseProvider).songDao,
  name: 'songDaoProvider',
);

/// 设置 DAO
final settingsDaoProvider = Provider<SettingsDao>(
  (ref) => ref.watch(appDatabaseProvider).settingsDao,
  name: 'settingsDaoProvider',
);

/// 歌单 DAO
final playlistDaoProvider = Provider<PlaylistDao>(
  (ref) => ref.watch(appDatabaseProvider).playlistDao,
  name: 'playlistDaoProvider',
);

/// 收藏 DAO
final favoritesDaoProvider = Provider<FavoritesDao>(
  (ref) => ref.watch(appDatabaseProvider).favoritesDao,
  name: 'favoritesDaoProvider',
);

// ==================== 演示曲库（真实源的数据视图） ====================

/// 演示曲库的音乐源实例（壳工程注册它；测试里直接构造）
final catalogSourceProvider = Provider<CatalogMusicSource>(
  (ref) => CatalogMusicSource(),
  name: 'catalogSourceProvider',
);

/// 配表曲库（仅供「来源标签 / 流派 / 专辑封面」这类展示元数据使用）
final catalogProvider = Provider<Catalog>(
  (ref) => ref.watch(catalogSourceProvider).catalog,
  name: 'catalogProvider',
);

/// 曲目 id → [Song]（演示曲库曲目）
final catalogSongsProvider = Provider<Map<String, Song>>((ref) {
  final source = ref.watch(catalogSourceProvider);
  return {
    for (final track in source.catalog.tracks) track.id: source.songOf(track),
  };
}, name: 'catalogSongsProvider');

/// 曲目 id → [CatalogTrack]（展示元数据：封面、时长、专辑、流派）
final catalogTracksProvider = Provider<Map<String, CatalogTrack>>((ref) {
  final catalog = ref.watch(catalogProvider);
  return {for (final track in catalog.tracks) track.id: track};
}, name: 'catalogTracksProvider');

/// 播放器如实报出的「当前曲目对象」（整首 Song，不是只有 id）
///
/// 为什么需要它：换队列后「正在播的那首」可能已经不在新队列里（真机场景：
/// A 在播时点一首播不出来的 B，队列被换成 B 所在列表）。此时若只拿 id 去解析，
/// resolver 会先给一个「标题 = id」的占位 —— 播放条标题于是显示成 "2"
/// （A 是 歌曲宝 id=2 的素颜）。所以把播放器给的完整对象留在内存里，UI 优先用它。
class PlayerCurrentSongNotifier extends Notifier<Song?> {
  @override
  Song? build() => null;

  /// 播放器广播当前曲目时同步（含"换队列后仍如实报在播那首"）
  void set(Song? song) => state = song;
}

/// 播放器当前曲目对象 Provider
final playerCurrentSongProvider =
    NotifierProvider<PlayerCurrentSongNotifier, Song?>(
        PlayerCurrentSongNotifier.new);

/// 当前播放曲目 id → [Song]
final currentSongProvider = Provider<Song?>((ref) {
  final id = ref.watch(currentTrackIdProvider);
  if (id == null) return null;
  // ① 播放器给的完整对象（换队列后它可能不在队列里，但字段是全的）
  final playing = ref.watch(playerCurrentSongProvider);
  if (playing != null && playing.globalKey == id) return playing;
  // ② 队列里的同一个 Song：队列里放的是完整对象（标题/艺人/封面都在）。
  // 只走 resolver 的话，远程源会先给一个「标题=id」的占位，异步补齐后又不通知，
  // 表现就是播放页标题显示成一串数字、封面空白。
  for (final song in ref.watch(queueProvider)) {
    if (song.globalKey == id) return song;
  }
  return ref.watch(songResolverProvider)(id);
}, name: 'currentSongProvider');

/// 曲目 id 解析器：先把 id 当全局键（sourceId:id）再当演示曲库 id
///
/// 说明：播放可能来自任意源，这里统一走一个入口解析成 [Song]，
/// 页面只依赖 [Song] 的可空字段，不再假设「曲目一定在配表里」。
final songResolverProvider = Provider<Song? Function(String?)>((ref) {
  final manager = ref.watch(sourceManagerProvider);
  final catalogSongs = ref.watch(catalogSongsProvider);
  final byKey = <String, Song>{};

  /// 从曲库缓存里按 id 找
  Song? fromCache(String id) {
    final direct = catalogSongs[id];
    if (direct != null) return direct;
    for (final song in catalogSongs.values) {
      if (song.id == id) return song;
    }
    return null;
  }

  return (String? rawId) {
    if (rawId == null || rawId.isEmpty) return null;
    final cached = fromCache(rawId);
    if (cached != null) return cached;
    final hit = byKey[rawId];
    if (hit != null) return hit;

    // 全局键形式：sourceId:id
    final parts = rawId.split(':');
    if (parts.length == 2) {
      final source = manager.getSource(parts.first);
      if (source != null) {
        // 同步视角下先给一个占位 Song，随后由异步 provider 补齐详情
        final placeholder = Song(
          id: parts[1],
          sourceId: parts.first,
          title: parts[1],
          artist: '',
        );
        byKey[rawId] = placeholder;
        unawaited(() async {
          try {
            byKey[rawId] = await source.getSongDetail(parts[1]);
          } catch (_) {
            // 回源失败时保留占位（下次进入会再试）
          }
        }());
        return placeholder;
      }
    }
    return null;
  };
}, name: 'songResolverProvider');

/// 异步取任意 id 的歌曲详情（远程源首次进入时会补一次）
final songByIdProvider = FutureProvider.family<Song?, String>((ref, id) async {
  final catalogSongs = ref.watch(catalogSongsProvider);
  if (catalogSongs.containsKey(id)) return catalogSongs[id];
  final parts = id.split(':');
  if (parts.length != 2) return null;
  final source = ref.watch(sourceManagerProvider).getSource(parts.first);
  if (source == null) return null;
  try {
    return await source.getSongDetail(parts[1]);
  } catch (_) {
    return null;
  }
}, name: 'songByIdProvider');

// ==================== 展示配表常量（原型文案/选项） ====================

// 最近播放上限（kRecentMax）等原型常量统一定义在 data/catalog.dart，
// 这里不再重复声明，避免 uiv2.dart 顶层导出时的合并冲突。

// ==================== 主题与外观（全部持久化到 settings） ====================

/// 主题模式（原型 store.theme：'dark' / 'light'）
class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const String key = 'theme_mode';

  @override
  ThemeMode build() {
    load();
    return ThemeMode.dark;
  }

  /// 从 settings 恢复
  Future<void> load() async {
    final raw = await ref.read(settingsDaoProvider).get(key);
    switch (raw) {
      case 'light':
        state = ThemeMode.light;
      case 'dark':
        state = ThemeMode.dark;
      case 'system':
        state = ThemeMode.system;
    }
  }

  /// 设置主题模式并持久化
  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await ref.read(settingsDaoProvider).set(
          key,
          switch (mode) {
            ThemeMode.light => 'light',
            ThemeMode.dark => 'dark',
            ThemeMode.system => 'system',
          },
        );
  }

  /// 在明暗之间切换（原型「深色主题」开关）
  Future<void> toggleDark() => setMode(
        state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
      );
}

/// 主题模式 Provider
final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// 仅 Wi-Fi 下载（原型 store.wifiOnly）
class WifiOnlyNotifier extends Notifier<bool> {
  static const String key = 'wifi_only';

  @override
  bool build() {
    load();
    return true;
  }

  /// 从 settings 恢复
  Future<void> load() async {
    final raw = await ref.read(settingsDaoProvider).get(key);
    if (raw != null) state = raw == '1';
  }

  /// 设置并持久化
  Future<void> set(bool value) async {
    state = value;
    await ref.read(settingsDaoProvider).set(key, value ? '1' : '0');
  }
}

/// 仅 Wi-Fi 下载 Provider
final wifiOnlyProvider =
    NotifierProvider<WifiOnlyNotifier, bool>(WifiOnlyNotifier.new);

/// 播放设备名（原型 store.device）
class DeviceNotifier extends Notifier<String> {
  static const String key = 'play_device';

  @override
  String build() {
    load();
    return kDeviceOptions.first.name;
  }

  /// 从 settings 恢复
  Future<void> load() async {
    final raw = await ref.read(settingsDaoProvider).get(key);
    if (raw != null && raw.isNotEmpty) state = raw;
  }

  /// 设置并持久化
  Future<void> set(String name) async {
    state = name;
    await ref.read(settingsDaoProvider).set(key, name);
  }
}

/// 播放设备 Provider
final deviceProvider = NotifierProvider<DeviceNotifier, String>(DeviceNotifier.new);

/// 本地扫描目录（settings key = scan_dir，与 ui 包共用同一个键）
final scanDirProvider = FutureProvider<String?>(
  (ref) => ref.watch(settingsDaoProvider).get('scan_dir'),
  name: 'scanDirProvider',
);

// ==================== 收藏（真实 DAO） ====================

/// 收藏集合（[FavoriteRecord] 列表，新→旧按时间倒序）
class LikedNotifier extends Notifier<List<FavoriteRecord>> {
  @override
  List<FavoriteRecord> build() {
    load();
    return const [];
  }

  /// 从数据库加载收藏记录（含 title/artist/cover 快照）
  Future<void> load() async {
    final records = await ref.read(favoritesDaoProvider).getAllFavoriteRecords();
    final sorted = List.of(records)
      ..sort((a, b) => b.time.compareTo(a.time)); // 新的在前
    state = sorted;
  }

  /// 某个全局键是否已收藏
  bool containsKey(String songKey) =>
      state.any((r) => r.songKey == songKey);

  /// 切换收藏（写库后重载）
  Future<void> toggle(Song song) async {
    final dao = ref.read(favoritesDaoProvider);
    if (await dao.isFavorite(song.globalKey)) {
      await dao.removeFavorite(song.globalKey);
    } else {
      // 关键：写库时必须带元数据快照（规则源详情不返回标题，见 core 的 Playlist 注释）
      await dao.addFavorite(
        song.globalKey,
        DateTime.now().millisecondsSinceEpoch,
        title: song.title,
        artist: song.artist,
        coverUrl: song.coverUrl,
      );
    }
    await load();
  }
}

/// 收藏 Provider
final likedProvider =
    NotifierProvider<LikedNotifier, List<FavoriteRecord>>(LikedNotifier.new);

/// 收藏歌曲（把记录还原成 [Song]，供列表渲染）
final likedSongsProvider = Provider<List<Song>>((ref) {
  final records = ref.watch(likedProvider);
  return records.map((r) {
    final parts = r.songKey.split(':');
    return Song(
      id: parts.length == 2 ? parts[1] : r.songKey,
      sourceId: parts.isNotEmpty ? parts.first : 'unknown',
      title: r.title ?? '',
      artist: r.artist ?? '',
      coverUrl: r.coverUrl,
    );
  }).toList();
}, name: 'likedSongsProvider');

/// 收藏数（「我的」页统计卡）
final favoriteCountProvider = Provider<int>(
  (ref) => ref.watch(likedProvider).length,
  name: 'favoriteCountProvider',
);

// ==================== 最近播放（真实服务 + 快照） ====================

/// 最近播放记录（[RecentPlayRecord]：songKey + 播放时间 + 元数据快照）
class RecentNotifier extends Notifier<List<RecentPlayRecord>> {
  @override
  List<RecentPlayRecord> build() {
    load();
    return const [];
  }

  /// 从服务加载（新→旧）
  Future<void> load() async {
    final records =
        await ref.read(recentPlaysServiceProvider).getRecentPlayRecords();
    state = records;
  }

  /// 记录一次播放（服务内部负责去重移顶与上限清理）
  Future<void> record(Song song) async {
    await ref.read(recentPlaysServiceProvider).recordPlay(song);
    await load();
  }

  /// 清空最近播放
  Future<void> clear() async {
    await ref.read(recentPlaysServiceProvider).clear();
    await load();
  }
}

/// 最近播放 Provider
final recentProvider =
    NotifierProvider<RecentNotifier, List<RecentPlayRecord>>(RecentNotifier.new);

/// 最近播放歌曲（用记录里的快照还原，避免回源）
final recentSongsProvider = Provider<List<Song>>((ref) {
  final records = ref.watch(recentProvider);
  return records.map((r) {
    final parts = r.songKey.split(':');
    return Song(
      id: parts.length == 2 ? parts[1] : r.songKey,
      sourceId: parts.isNotEmpty ? parts.first : 'unknown',
      title: r.title ?? '',
      artist: r.artist ?? '',
      coverUrl: r.coverUrl,
    );
  }).toList();
}, name: 'recentSongsProvider');

// ==================== 自建歌单（真实 DAO） ====================

/// 歌单列表（[Playlist]，含歌曲快照）
final playlistsProvider = FutureProvider<List<Playlist>>((ref) async {
  final list = await ref.watch(playlistDaoProvider).getAllPlaylists();
  list.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
  return list;
}, name: 'playlistsProvider');

/// 自建歌单（sourceId 为空）：保留 AsyncValue，页面可直接 .when
///
/// 收藏的远端歌单与自建歌单同表存放，但语义不同：
/// 「我的歌单」只认自建，「收藏歌单」只认 sourceId 非空的。
final ownedPlaylistsProvider = Provider<AsyncValue<List<Playlist>>>((ref) {
  return ref.watch(playlistsProvider).whenData((all) => all
      .where((p) => (p.sourceId ?? '').isEmpty)
      .toList(growable: false));
}, name: 'ownedPlaylistsProvider');

/// 收藏的远端歌单（sourceId 非空）
final favoritePlaylistsProvider = Provider<List<Playlist>>((ref) {
  final all = ref.watch(playlistsProvider).value ?? const <Playlist>[];
  return all.where((p) => (p.sourceId ?? '').isNotEmpty).toList(growable: false);
}, name: 'favoritePlaylistsProvider');

/// 歌单按 id 查询
final playlistByIdProvider =
    FutureProvider.family<Playlist?, String>((ref, id) async {
  return ref.watch(playlistDaoProvider).getPlaylist(id);
}, name: 'playlistByIdProvider');

/// 歌单写操作（新建 / 重命名 / 增删歌曲 / 删除）
class PlaylistActions {
  /// Riverpod 引用
  final Ref ref;

  /// 构造写操作
  PlaylistActions(this.ref);

  PlaylistDao get _dao => ref.read(playlistDaoProvider);

  /// 新建歌单（返回新歌单 id）
  Future<String> create(String name, {String? description}) async {
    final now = DateTime.now();
    final id = 'up-${now.microsecondsSinceEpoch}';
    await _dao.insertPlaylist(Playlist(
      id: id,
      name: name,
      songKeys: const [],
      songSnapshots: const {},
      createdTime: now,
      modifiedTime: now,
    ));
    ref.invalidate(playlistsProvider);
    return id;
  }

  /// 重命名歌单（可同时改简介，简介写入 sourcePlaylistId 之外的展示字段）
  Future<void> rename(String id, String name) async {
    final playlist = await _dao.getPlaylist(id);
    if (playlist == null) return;
    await _dao.updatePlaylist(playlist.copyWith(
      name: name,
      modifiedTime: DateTime.now(),
    ));
    ref.invalidate(playlistsProvider);
    ref.invalidate(playlistByIdProvider(id));
  }

  /// 删除歌单
  Future<void> delete(String id) async {
    await _dao.deletePlaylist(id);
    ref.invalidate(playlistsProvider);
    ref.invalidate(playlistByIdProvider(id));
  }

  /// 补齐缺失的曲目元数据
  ///
  /// 规则源的 getSongDetail 只返回播放地址；把这种 Song 直接存成歌单快照，
  /// 详情页就会显示「(未知曲目) / 0:00」。这里用源详情把缺失字段补上。
  Future<Song> _completeMetadata(Song song) async {
    if (song.title.isNotEmpty && song.artist.isNotEmpty) return song;

    // 1) 源详情：规则源通常只回播放地址，但能补多少补多少
    var merged = song;
    try {
      final detail = await ref
          .read(sourceManagerProvider)
          .getSongDetail(song.sourceId, song.id);
      merged = _mergeMetadata(merged, detail);
    } catch (_) {
      // 源不可用就跳过，继续用其它来源补
    }
    if (merged.title.isNotEmpty) return merged;

    // 2) 最近播放：播过的曲子在这里留有完整元数据快照
    for (final recent in ref.read(recentSongsProvider)) {
      if (recent.globalKey == song.globalKey) {
        merged = _mergeMetadata(merged, recent);
        break;
      }
    }
    return merged;
  }

  /// 用 [other] 的非空字段补齐 [base] 的空字段（与全局元数据缓存共用一套规则）
  Song _mergeMetadata(Song base, Song other) => mergeSongMetadata(base, other);

  /// 收藏远端歌单（写入 playlists 表；sourceId 非空即"来源歌单"）
  ///
  /// 幂等：同一 `sourceId + sourcePlaylistId` 已收藏时直接返回已有 id。
  Future<String> favoriteRemote({
    required String sourceId,
    required String sourcePlaylistId,
    required String name,
    String? coverUrl,
  }) async {
    final all = await _dao.getAllPlaylists();
    for (final p in all) {
      if (p.sourceId == sourceId && p.sourcePlaylistId == sourcePlaylistId) {
        return p.id;
      }
    }
    final now = DateTime.now();
    final id = 'fav-${now.microsecondsSinceEpoch}';
    await _dao.insertPlaylist(Playlist(
      id: id,
      name: name,
      sourceId: sourceId,
      sourcePlaylistId: sourcePlaylistId,
      coverUrl: coverUrl,
      createdTime: now,
      modifiedTime: now,
    ));
    ref.invalidate(playlistsProvider);
    return id;
  }

  /// 取消收藏（只删这一行，不动其它歌单）
  Future<void> unfavorite(String playlistId) async {
    await _dao.deletePlaylist(playlistId);
    ref.invalidate(playlistsProvider);
    ref.invalidate(playlistByIdProvider(playlistId));
  }

  /// 加入一首歌（带元数据快照）
  Future<bool> addSong(String playlistId, Song song) async {
    final enriched = await _completeMetadata(song);
    final playlist = await _dao.getPlaylist(playlistId);
    if (playlist == null) return false;
    final key = enriched.globalKey;
    if (playlist.songKeys.contains(key)) return false;
    await _dao.updatePlaylist(playlist.copyWith(
      songKeys: [...playlist.songKeys, key],
      songSnapshots: {...playlist.songSnapshots, key: enriched},
      modifiedTime: DateTime.now(),
    ));
    ref.invalidate(playlistsProvider);
    ref.invalidate(playlistByIdProvider(playlistId));
    return true;
  }

  /// 移出一首歌
  Future<bool> removeSong(String playlistId, String songKey) async {
    final playlist = await _dao.getPlaylist(playlistId);
    if (playlist == null) return false;
    if (!playlist.songKeys.contains(songKey)) return false;
    final keys = List.of(playlist.songKeys)..remove(songKey);
    final snapshots = Map.of(playlist.songSnapshots)..remove(songKey);
    await _dao.updatePlaylist(playlist.copyWith(
      songKeys: keys,
      songSnapshots: snapshots,
      modifiedTime: DateTime.now(),
    ));
    ref.invalidate(playlistsProvider);
    ref.invalidate(playlistByIdProvider(playlistId));
    return true;
  }

  /// 歌单里的歌曲（优先用快照，缺失时回源补详情）
  Future<List<Song>> songsOf(Playlist playlist) async {
    final manager = ref.read(sourceManagerProvider);

    // 来源歌单（收藏的远端歌单）：曲目直接问源，不依赖本地快照
    final srcId = playlist.sourceId ?? '';
    if (srcId.isNotEmpty) {
      final source = manager.getSource(srcId);
      final remoteId = playlist.sourcePlaylistId ?? playlist.id;
      if (source != null) {
        try {
          final songs = await source.getPlaylistSongs(remoteId);
          if (songs.isNotEmpty) return songs;
        } catch (_) {
          // 源不可用时退回快照/详情路径
        }
      }
    }
    final out = <Song>[];
    for (final key in playlist.songKeys) {
      final snapshot = playlist.songSnapshots[key];
      if (snapshot != null && snapshot.title.isNotEmpty) {
        out.add(snapshot);
        continue;
      }
      // 快照存在但元数据是空的（历史数据）→ 回源补一次，并回写快照自愈
      if (snapshot != null) {
        final healed = await _completeMetadata(snapshot);
        if (healed.title.isNotEmpty) {
          await _dao.updatePlaylist(playlist.copyWith(
            songSnapshots: {...playlist.songSnapshots, key: healed},
          ));
          ref.invalidate(playlistByIdProvider(playlist.id));
        }
        out.add(healed);
        continue;
      }
      final parts = key.split(':');
      if (parts.length != 2) continue;
      try {
        final song = await manager.getSongDetail(parts[0], parts[1]);
        out.add(song);
      } catch (_) {
        // 源不可用时跳过这一首，不影响其它
      }
    }
    return out;
  }
}

/// 歌单写操作 Provider
final playlistActionsProvider = Provider<PlaylistActions>(
  (ref) => PlaylistActions(ref),
  name: 'playlistActionsProvider',
);

/// 远程歌单（不落库）：路由参数 `<sourceId>::<playlistId>`
///
/// 点开远端歌单不写库，直接问源要详情；要收藏再走 [PlaylistActions.favoriteRemote]。
final remotePlaylistProvider =
    FutureProvider.family<Playlist?, String>((ref, param) async {
  final parts = param.split('::');
  if (parts.length != 2) return null;
  final source = ref.watch(sourceManagerProvider).getSource(parts[0]);
  if (source == null) return null;
  try {
    return await source.getPlaylist(parts[1]);
  } catch (_) {
    return null;
  }
}, name: 'remotePlaylistProvider');

/// 远程歌单的曲目（直接来自源）
final remotePlaylistSongsProvider =
    FutureProvider.family<List<Song>, String>((ref, param) async {
  final parts = param.split('::');
  if (parts.length != 2) return const [];
  final source = ref.watch(sourceManagerProvider).getSource(parts[0]);
  if (source == null) return const [];
  try {
    return await source.getPlaylistSongs(parts[1]);
  } catch (_) {
    return const [];
  }
}, name: 'remotePlaylistSongsProvider');

/// 某个歌单的歌曲列表（快照优先）
final playlistSongsProvider =
    FutureProvider.family<List<Song>, String>((ref, id) async {
  final playlist = await ref.watch(playlistByIdProvider(id).future);
  if (playlist == null) return const [];
  return ref.watch(playlistActionsProvider).songsOf(playlist);
}, name: 'playlistSongsProvider');

// ==================== 本地音乐（真实扫描源） ====================

/// 本地扫描源（core 的 LocalScanSource；未注册时为 null）
final localScanSourceProvider = Provider<LocalScanSource?>((ref) {
  final source = ref.watch(sourceManagerProvider).getSource('local_scan');
  return source is LocalScanSource ? source : null;
}, name: 'localScanSourceProvider');

/// 本地曲目列表（来自扫描缓存）
class LocalTracksNotifier extends Notifier<List<Song>> {
  @override
  List<Song> build() {
    load();
    return const [];
  }

  /// 从扫描源缓存加载
  Future<void> load() async {
    final source = ref.read(localScanSourceProvider);
    if (source == null) {
      state = const [];
      return;
    }
    try {
      await source.loadFromDatabase();
    } catch (_) {
      // 首次未扫描时忽略
    }
    state = source.getScannedSongs();
  }
}

/// 本地曲目 Provider
final localTracksProvider =
    NotifierProvider<LocalTracksNotifier, List<Song>>(LocalTracksNotifier.new);

/// 按文件夹分组的本地曲目（文件夹名取 localPath 的目录名，真实数据无目录时归「本地音乐」）
final localFoldersProvider = Provider<List<LocalFolder>>((ref) {
  final songs = ref.watch(localTracksProvider);
  final map = <String, List<Song>>{};
  for (final song in songs) {
    final path = song.localPath ?? '';
    final name = _folderNameOf(path);
    map.putIfAbsent(name, () => <Song>[]).add(song);
  }
  final out = map.entries
      .map((e) => LocalFolder(name: e.key, songs: e.value))
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  return out;
}, name: 'localFoldersProvider');

/// 从文件路径取文件夹展示名（取父目录名；无路径归「本地音乐」）
String _folderNameOf(String path) {
  if (path.isEmpty) return '本地音乐';
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((s) => s.isNotEmpty).toList();
  if (parts.length < 2) return '本地音乐';
  return parts[parts.length - 2];
}

/// 本地文件夹分组
class LocalFolder {
  /// 文件夹展示名
  final String name;

  /// 该文件夹下的曲目
  final List<Song> songs;

  /// 构造分组
  const LocalFolder({required this.name, required this.songs});

  /// 总时长
  Duration get totalDuration => Duration(
        seconds: songs.fold<int>(0, (sum, s) => sum + (s.duration ?? 0)),
      );
}

// ==================== 搜索历史 ====================

/// 搜索历史（settings key = ui_search_history，每行一条）
class SearchHistoryNotifier extends Notifier<List<String>> {
  static const int _maxEntries = 20;
  static const String key = 'search_history';

  @override
  List<String> build() {
    load();
    return const [];
  }

  /// 从 settings 恢复（v1/ui 包用 JSON 数组存同一键，保持格式一致才能互相读到）
  Future<void> load() async {
    final raw = await ref.read(settingsDaoProvider).get(key);
    if (raw == null || raw.isEmpty) return;
    try {
      state = (jsonDecode(raw) as List<dynamic>).cast<String>();
    } catch (_) {
      state = const [];
    }
  }

  /// 记录一次搜索（去重移顶 + 上限）
  Future<void> add(String keyword) async {
    final k = keyword.trim();
    if (k.isEmpty) return;
    final updated = [k, ...state.where((e) => e != k)].take(_maxEntries).toList();
    state = updated;
    await ref.read(settingsDaoProvider).set(key, jsonEncode(updated));
  }

  /// 清空历史
  Future<void> clear() async {
    state = const [];
    await ref.read(settingsDaoProvider).set(key, '[]');
  }
}

/// 搜索历史 Provider
final searchHistoryProvider =
    NotifierProvider<SearchHistoryNotifier, List<String>>(
        SearchHistoryNotifier.new);

// ==================== 搜索状态（真实聚合搜索） ====================

/// 搜索结果里的「来源」分组
class SearchPool {
  /// 来源 id
  final String id;

  /// 来源展示名
  final String name;

  /// 该来源的命中歌曲
  final List<Song> songs;

  /// 构造来源分组
  const SearchPool({
    required this.id,
    required this.name,
    required this.songs,
  });
}

/// 搜索状态
class SearchState {
  /// 关键词
  final String keyword;

  /// 命中总数
  final int total;

  /// 按来源分组
  final List<SearchPool> pools;

  /// 当前来源筛选（all / <sourceId>）
  final String sourceFilter;

  /// 是否展开全部命中
  final bool expanded;

  /// 是否正在搜索
  final bool loading;

  /// 是否还有更多（任一源返回 hasMore）
  final bool hasMore;

  /// 构造搜索状态
  const SearchState({
    this.keyword = '',
    this.total = 0,
    this.pools = const [],
    this.sourceFilter = 'all',
    this.expanded = false,
    this.loading = false,
    this.hasMore = false,
  });

  /// 当前筛选下可见的歌曲
  List<Song> visibleSongs({int limit = 10}) {
    final active = activePools;
    final merged = [for (final p in active) ...p.songs];
    return expanded ? merged : merged.take(limit).toList();
  }

  /// 当前筛选下的命中数
  int get filteredTotal => activePools.fold(0, (sum, p) => sum + p.songs.length);

  /// 参与筛选的分组
  List<SearchPool> get activePools => sourceFilter == 'all'
      ? pools
      : pools.where((p) => p.id == sourceFilter).toList();

  /// 复制并覆盖字段
  SearchState copyWith({
    String? keyword,
    int? total,
    List<SearchPool>? pools,
    String? sourceFilter,
    bool? expanded,
    bool? loading,
    bool? hasMore,
  }) =>
      SearchState(
        keyword: keyword ?? this.keyword,
        total: total ?? this.total,
        pools: pools ?? this.pools,
        sourceFilter: sourceFilter ?? this.sourceFilter,
        expanded: expanded ?? this.expanded,
        loading: loading ?? this.loading,
        hasMore: hasMore ?? this.hasMore,
      );
}

/// 搜索 Notifier —— 走 [SourceManager.searchAll] 的真实聚合搜索
class SearchNotifier extends Notifier<SearchState> {
  @override
  SearchState build() => const SearchState();

  /// 执行搜索（静默失败：单源异常不会打断整体）
  Future<void> search(String keyword, {bool recordHistory = false}) async {
    final q = keyword.trim();
    if (recordHistory) {
      await ref.read(searchHistoryProvider.notifier).add(q);
    }
    if (q.isEmpty) {
      state = const SearchState();
      return;
    }
    state = SearchState(keyword: q, loading: true);
    final manager = ref.read(sourceManagerProvider);
    try {
      final results = await manager.searchAll(keyword: q);
      final pools = <SearchPool>[];
      var total = 0;
      var hasMore = false;
      for (final r in results) {
        if (r.songs.isEmpty) continue;
        final name = manager.getSource(r.sourceId)?.sourceInfo.name ?? r.sourceId;
        pools.add(SearchPool(id: r.sourceId, name: name, songs: r.songs));
        total += r.songs.length;
        hasMore = hasMore || r.hasMore;
      }
      state = SearchState(
        keyword: q,
        total: total,
        pools: pools,
        hasMore: hasMore,
      );
    } catch (_) {
      state = SearchState(keyword: q, loading: false);
    }
  }

  /// 切换来源筛选
  void setSourceFilter(String filter) =>
      state = state.copyWith(sourceFilter: filter, expanded: false);

  /// 展开 / 收起全部命中
  void toggleExpanded() => state = state.copyWith(expanded: !state.expanded);

  /// 清空搜索
  void clear() => state = const SearchState();
}

/// 搜索 Provider
final searchProvider =
    NotifierProvider<SearchNotifier, SearchState>(SearchNotifier.new);

// ==================== 播放状态 ====================

/// 当前播放曲目 id（全局键优先，演示曲目用曲目 id）
class CurrentTrackNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// 设置当前曲目
  void set(String? trackId) => state = trackId;
}

/// 当前曲目 Provider
final currentTrackIdProvider =
    NotifierProvider<CurrentTrackNotifier, String?>(CurrentTrackNotifier.new);

/// 播放队列（[Song] 列表，与底层播放器保持同步）
class QueueNotifier extends Notifier<List<Song>> {
  @override
  List<Song> build() => const [];

  /// 覆盖队列
  void set(List<Song> songs) => state = List.of(songs);

  /// 追加到队尾
  void append(Song song) => state = [...state, song];

  /// 插入到指定下标
  void insertAt(int index, Song song) {
    final next = List.of(state);
    next.insert(index.clamp(0, next.length), song);
    state = next;
  }

  /// 移除指定下标（返回被移除的歌曲）
  Song? removeAt(int index) {
    if (index < 0 || index >= state.length) return null;
    final next = List.of(state);
    final removed = next.removeAt(index);
    state = next;
    return removed;
  }

  /// 移动到新下标
  void move(int from, int to) {
    if (from < 0 || from >= state.length) return;
    final next = List.of(state);
    final moving = next.removeAt(from);
    next.insert(to.clamp(0, next.length), moving);
    state = next;
  }

  /// 某首歌是否在队列里
  bool containsKey(String songKey) =>
      state.any((s) => s.globalKey == songKey);
}

/// 队列 Provider
final queueProvider = NotifierProvider<QueueNotifier, List<Song>>(QueueNotifier.new);

/// 是否正在播放
class IsPlayingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// 设置播放态
  void set(bool value) => state = value;
}

/// 播放态 Provider
final isPlayingProvider =
    NotifierProvider<IsPlayingNotifier, bool>(IsPlayingNotifier.new);

/// 正在解析播放地址的曲目全局键（原型 player.pending）
class PendingNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// 设置准备中的曲目
  void set(String? songKey) => state = songKey;
}

/// 准备播放 Provider
final pendingProvider =
    NotifierProvider<PendingNotifier, String?>(PendingNotifier.new);

/// 播放进度
class PositionNotifier extends Notifier<Duration> {
  @override
  Duration build() => Duration.zero;

  /// 更新进度
  void set(Duration value) => state = value;
}

/// 播放进度 Provider
final positionProvider =
    NotifierProvider<PositionNotifier, Duration>(PositionNotifier.new);

/// 当前曲目总时长
class DurationNotifier extends Notifier<Duration> {
  @override
  Duration build() => Duration.zero;

  /// 更新时长
  void set(Duration value) => state = value;
}

/// 总时长 Provider
final durationProvider =
    NotifierProvider<DurationNotifier, Duration>(DurationNotifier.new);

/// 音量与静音
class VolumeState {
  /// 当前音量（0~1）
  final double volume;

  /// 最后一次非零音量（取消静音时恢复）
  final double lastVolume;

  /// 构造音量状态
  const VolumeState({this.volume = 0.8, this.lastVolume = 0.8});

  /// 是否静音
  bool get muted => volume <= 0;

  /// 复制并覆盖
  VolumeState copyWith({double? volume, double? lastVolume}) => VolumeState(
        volume: volume ?? this.volume,
        lastVolume: lastVolume ?? this.lastVolume,
      );
}

/// 音量 Notifier（持久化到 settings）
class VolumeNotifier extends Notifier<VolumeState> {
  static const String key = 'volume';

  @override
  VolumeState build() {
    load();
    return const VolumeState();
  }

  /// 从 settings 恢复音量并写入播放器
  Future<void> load() async {
    final raw = await ref.read(settingsDaoProvider).get(key);
    final v = double.tryParse(raw ?? '');
    if (v == null) return;
    state = VolumeState(volume: v.clamp(0.0, 1.0), lastVolume: v <= 0 ? 0.8 : v);
    await ref.read(playerProvider).setVolume(state.volume);
  }

  /// 设置音量
  Future<void> setVolume(double value) async {
    final v = value.clamp(0.0, 1.0).toDouble();
    state = VolumeState(volume: v, lastVolume: v > 0 ? v : state.lastVolume);
    await ref.read(playerProvider).setVolume(v);
    await ref.read(settingsDaoProvider).set(key, v.toString());
  }

  /// 静音 / 取消静音
  Future<void> toggleMute() async {
    if (state.muted) {
      await setVolume(state.lastVolume <= 0 ? 0.8 : state.lastVolume);
    } else {
      state = state.copyWith(volume: 0);
      await ref.read(playerProvider).setVolume(0);
      await ref.read(settingsDaoProvider).set(key, '0');
    }
  }
}

/// 音量 Provider
final volumeProvider = NotifierProvider<VolumeNotifier, VolumeState>(VolumeNotifier.new);

/// 播放模式（映射 core 的 [PlayMode]，持久化到 settings key = play_mode）
class PlayModeNotifier extends Notifier<PlayMode> {
  static const String key = 'play_mode';

  @override
  PlayMode build() {
    load();
    return PlayMode.listLoop;
  }

  /// 从 settings 恢复并同步给播放器
  Future<void> load() async {
    final raw = await ref.read(settingsDaoProvider).get(key);
    final mode = switch (raw) {
      'single' => PlayMode.singleLoop,
      'shuffle' => PlayMode.shuffle,
      'sequential' => PlayMode.sequential,
      _ => PlayMode.listLoop,
    };
    state = mode;
    ref.read(playerProvider).playMode = mode;
  }

  /// 设置播放模式并持久化
  Future<void> set(PlayMode mode) async {
    state = mode;
    ref.read(playerProvider).playMode = mode;
    await ref.read(settingsDaoProvider).set(
          key,
          switch (mode) {
            PlayMode.listLoop => 'list',
            PlayMode.singleLoop => 'single',
            PlayMode.shuffle => 'shuffle',
            PlayMode.sequential => 'sequential',
          },
        );
  }

  /// 列表循环 → 单曲循环 → 顺序播放 轮转
  Future<void> cycle() => set(switch (state) {
        PlayMode.listLoop => PlayMode.singleLoop,
        PlayMode.singleLoop => PlayMode.sequential,
        PlayMode.sequential || PlayMode.shuffle => PlayMode.listLoop,
      });
}

/// 播放模式 Provider
final playModeProvider =
    NotifierProvider<PlayModeNotifier, PlayMode>(PlayModeNotifier.new);

/// 随机播放开关（原型 player.shuffle）
class ShuffleNotifier extends Notifier<bool> {
  static const String key = 'play_shuffle';

  @override
  bool build() {
    load();
    return false;
  }

  /// 从 settings 恢复
  Future<void> load() async {
    final raw = await ref.read(settingsDaoProvider).get(key);
    if (raw != null) state = raw == '1';
  }

  /// 设置并持久化
  Future<void> set(bool value) async {
    state = value;
    await ref.read(settingsDaoProvider).set(key, value ? '1' : '0');
  }

  /// 切换
  Future<void> toggle() => set(!state);
}

/// 随机播放 Provider
final shuffleProvider = NotifierProvider<ShuffleNotifier, bool>(ShuffleNotifier.new);

/// 睡眠定时器（不持久化，到点暂停播放）
class SleepTimerNotifier extends Notifier<Duration?> {
  Timer? _timer;

  @override
  Duration? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  /// 设定定时器（覆盖已有倒计时）
  void start(Duration duration) {
    _timer?.cancel();
    state = duration;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remain = state;
      if (remain == null) {
        _timer?.cancel();
        return;
      }
      final next = remain - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        _timer?.cancel();
        state = null;
        ref.read(playerProvider).pause();
      } else {
        state = next;
      }
    });
  }

  /// 取消定时器
  void cancel() {
    _timer?.cancel();
    state = null;
  }
}

/// 睡眠定时器 Provider
final sleepTimerProvider =
    NotifierProvider<SleepTimerNotifier, Duration?>(SleepTimerNotifier.new);

// ==================== 播放绑定与控制器 ====================

/// 播放器事件流绑定 —— 在 AppShell 顶层 watch 一次即可保持存活
final playerStreamBindingProvider = Provider<void>((ref) {
  final player = ref.watch(playerProvider);
  final subs = <StreamSubscription<dynamic>>[
    player.stateStream.listen((s) {
      ref.read(isPlayingProvider.notifier).set(s == PlayerState.playing);
    }),
    player.positionStream.listen((ms) {
      ref.read(positionProvider.notifier).set(Duration(milliseconds: ms));
    }),
    player.durationStream.listen((ms) {
      ref.read(durationProvider.notifier).set(Duration(milliseconds: ms));
      // 播放器实测时长回写：列表里 0:00 的曲目播一次就有真实时长了。
      // 注意 durationStream 往往早于 currentTrackId 落地，这里要退回播放器自己的当前曲目。
      final song = ref.read(currentSongProvider) ?? ref.read(playerProvider).currentSong;
      if (song != null) {
        unawaited(ref.read(songMetadataServiceProvider).saveDuration(song, ms));
      }
    }),
  ];
  // 唯一同步点：当前曲目只认播放器广播。点播 / 上一首 / 下一首 / 自动续播 / 跳播
  // 最终都会走到播放器的 _playIndex，因此页面显示不可能与正在播放的东西脱节。
  if (player is CurrentSongSource) {
    subs.add((player as CurrentSongSource).currentSongStream.listen((song) {
      ref.read(currentTrackIdProvider.notifier).set(song?.globalKey);
      // 同时留住完整对象：换队列后"在播的那首"可能不在队列里，
      // 只有 id 就会退化成「标题=id」的占位（真机：播放条标题显示成 "2"）
      ref.read(playerCurrentSongProvider.notifier).set(song);
      ref.read(queueProvider.notifier).set(player.queue);
      // 曲目一开始播就去取歌词并落库（点播/上一首/下一首/跳转/自动续播都走这里）：
      // 这样"打开歌词"时是直接读缓存，断网或源失效也还有词。
      // 旧实现要等歌词面板挂载才请求，即"显示时才取"，不满足离线要求。
      if (song != null) {
        unawaited(ref.read(songMetadataServiceProvider).ensureLyrics(song));
        // 起播成功后把音频另存一份：开关默认开；已下载/已有缓存会自动跳过；
        // 失败静默（下次再播会重试）。命中判断只认完整文件，绝不播半截文件。
        if (ref.read(audioCacheEnabledProvider)) {
          unawaited(ref.read(audioCacheProvider).cacheAfterPlay(
                song,
                song.playUrl ?? '',
                headers: ref
                    .read(sourceManagerProvider)
                    .playHeadersFor(song.sourceId),
              ));
        }
      }
    }));
  }
  ref.onDispose(() {
    for (final sub in subs) {
      sub.cancel();
    }
  });
}, name: 'playerStreamBindingProvider');

/// 播放控制器 —— 所有页面的统一播放入口
class PlaybackController {
  /// Riverpod 引用
  final Ref ref;

  /// 构造控制器
  PlaybackController(this.ref);

  Player get _player => ref.read(playerProvider);
  SourceManager get _sourceManager => ref.read(sourceManagerProvider);

  /// 播放一首歌：解析播放地址 → 播放 → 同步 UI 状态 → 记录最近播放。
  ///
  /// 返回值表示是否**真的开始播放**：源没给播放地址（例如演示曲库）时返回 false，
  /// 调用方据此提示用户，而不是让界面假装在播（核心注释明确 getSongUrl 可能为空串）。
  Future<bool> playSong(Song song) async {
    final pending = ref.read(pendingProvider.notifier);
    pending.set(song.globalKey);
    try {
      // 统一走「实际要播的地址」解析：已下载 → 播放缓存 → 源。
      // 前两者命中时完全不请求源（源失效/断网也能播）；回源那一趟顺带登记的
      // 元数据由下面的 enrich 复用，所以一次播放只请求一次详情。
      final url = await ref.read(playSourceResolverProvider)(song);
      if (url.isEmpty) {
        SourceLogBus.instance.emit(
          song.sourceId,
          SourceLogLevel.warn,
          '播放',
          'id=${song.id} 源未提供播放地址，未开始播放',
        );
        pending.set(null);
        return false;
      }
      final playable = song.copyWith(playUrl: url);
      await _player.play(playable);
      // 封面等元数据异步补齐：不阻塞起播，失败静默
      // （详情已在解析地址时登记，这里不会重复请求）
      unawaited(ref.read(songMetadataServiceProvider).enrich(playable));
      pending.set(null);
      ref.read(currentTrackIdProvider.notifier).set(playable.globalKey);
      ref.read(isPlayingProvider.notifier).set(true);
      ref.read(queueProvider.notifier).set(_player.queue);
      await ref.read(recentProvider.notifier).record(playable);
      return true;
    } catch (e) {
      pending.set(null);
      ref.read(isPlayingProvider.notifier).set(false);
      SourceLogBus.instance.emit(
        song.sourceId,
        SourceLogLevel.error,
        '播放',
        'id=${song.id} 播放失败: $e',
      );
      return false;
    }
  }

  /// 用队列替换播放器队列并从指定位置开始播放
  Future<bool> playQueue(List<Song> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) return false;
    _player.setQueue(songs);
    ref.read(queueProvider.notifier).set(songs);
    return playSong(songs[startIndex.clamp(0, songs.length - 1)]);
  }

  /// 随机顺序播放
  Future<bool> shuffleQueue(List<Song> songs) async {
    if (songs.isEmpty) return false;
    final shuffled = List.of(songs)..shuffle();
    return playQueue(shuffled);
  }

  /// 跳转到队列下标并播放
  Future<void> jumpTo(int index) async {
    await _player.jumpToIndex(index);
    final queue = _player.queue;
    if (index >= 0 && index < queue.length) {
      ref.read(currentTrackIdProvider.notifier).set(queue[index].globalKey);
      ref.read(isPlayingProvider.notifier).set(true);
    }
  }

  /// 播放 / 暂停
  Future<void> toggle() async {
    if (_player.currentState == PlayerState.playing) {
      await _player.pause();
      ref.read(isPlayingProvider.notifier).set(false);
      return;
    }
    if (_player.currentState == PlayerState.idle && _player.queue.isEmpty) {
      return;
    }
    await _player.resume();
    ref.read(isPlayingProvider.notifier).set(true);
  }

  /// 下一首
  Future<void> next() async {
    await _player.next();
    final queue = _player.queue;
    final index = _player.currentIndex;
    if (index >= 0 && index < queue.length) {
      ref.read(currentTrackIdProvider.notifier).set(queue[index].globalKey);
      ref.read(isPlayingProvider.notifier).set(true);
    }
  }

  /// 上一首
  Future<void> previous() async {
    await _player.previous();
    final queue = _player.queue;
    final index = _player.currentIndex;
    if (index >= 0 && index < queue.length) {
      ref.read(currentTrackIdProvider.notifier).set(queue[index].globalKey);
      ref.read(isPlayingProvider.notifier).set(true);
    }
  }

  /// 按比例 seek
  Future<void> seekRatio(double ratio) async {
    final total = ref.read(durationProvider);
    if (total <= Duration.zero) return;
    await _player.seek(total * ratio.clamp(0, 1));
  }

  /// 追加到队尾（同步播放器队列与 UI 队列）
  void addToQueue(Song song) {
    final next = [..._player.queue, song];
    _player.setQueue(next);
    ref.read(queueProvider.notifier).set(next);
  }

  /// 插入到当前曲目之后
  void playNextUp(Song song) {
    final queue = List.of(_player.queue);
    final at = ref.read(currentTrackIdProvider) == null ? 0 : _player.currentIndex + 1;
    queue.insert(at.clamp(0, queue.length), song);
    _player.setQueue(queue);
    ref.read(queueProvider.notifier).set(queue);
  }

  /// 从队列移除下标（返回被移除的歌曲）
  Song? removeFromQueue(int index) {
    final queue = List.of(_player.queue);
    if (index < 0 || index >= queue.length) return null;
    final removed = queue.removeAt(index);
    _player.setQueue(queue);
    ref.read(queueProvider.notifier).set(queue);
    return removed;
  }

  /// 用新顺序覆盖队列（拖动排序用）
  void reorderQueue(int from, int to) {
    final queue = List.of(_player.queue);
    if (from < 0 || from >= queue.length) return;
    final moving = queue.removeAt(from);
    queue.insert(to.clamp(0, queue.length), moving);
    _player.setQueue(queue);
    ref.read(queueProvider.notifier).set(queue);
  }

  /// 清空队列（默认保留当前播放的那首）
  void clearQueue({bool keepCurrent = true}) {
    final currentKey = ref.read(currentTrackIdProvider);
    final kept = keepCurrent
        ? _player.queue.where((s) => s.globalKey == currentKey).toList()
        : <Song>[];
    _player.setQueue(kept);
    ref.read(queueProvider.notifier).set(kept);
  }
}

// ==================== 曲目元数据缓存（songs 表） ====================

/// 合并两首曲目的元数据：**只补空，绝不覆盖已有值**
Song mergeSongMetadata(Song base, Song other) {
  return base.copyWith(
    title: base.title.isEmpty ? other.title : base.title,
    artist: base.artist.isEmpty ? other.artist : base.artist,
    album: base.album ?? other.album,
    coverUrl: (base.coverUrl ?? '').isEmpty ? other.coverUrl : base.coverUrl,
    duration: (base.duration ?? 0) > 0 ? base.duration : other.duration,
    playUrl: base.playUrl ?? other.playUrl,
    lyricUrl: base.lyricUrl ?? other.lyricUrl,
    // 歌词也要"只补空"：否则后续任何一次时长/封面回写（REPLACE 语义）
    // 都会把已缓存的歌词抹掉，歌词缓存等于白做（真机端到端抓到的 bug）
    lyric: (base.lyric ?? '').isEmpty ? other.lyric : base.lyric,
  );
}

/// 元数据缓存版本号：写库后自增，页面 watch 它即可重建（不用整页 invalidate）
class SongMetaVersion extends Notifier<int> {
  @override
  int build() => 0;

  /// 有元数据写入时调用
  void bump() => state++;
}

/// 元数据缓存版本 Provider
final songMetaVersionProvider =
    NotifierProvider<SongMetaVersion, int>(SongMetaVersion.new);

/// 全部缓存曲目（globalKey → Song），来自 songs 表
final songMetaMapProvider = FutureProvider<Map<String, Song>>((ref) async {
  ref.watch(songMetaVersionProvider);
  final all = await ref.watch(songDaoProvider).searchSongs('');
  return {for (final s in all) s.globalKey: s};
}, name: 'songMetaMapProvider');

// ==================== 播放缓存（离线可用） ====================

/// 播放缓存实现（壳工程 override 为 AudioCacheImpl）
final audioCacheProvider = Provider<AudioCache>(
  (ref) => throw UnimplementedError('audioCacheProvider 必须被覆盖'),
  name: 'audioCacheProvider',
);

/// 播放时自动缓存（默认开）
class AudioCacheEnabledNotifier extends Notifier<bool> {
  /// settings 键
  static const String key = 'audio_cache_play';

  @override
  bool build() {
    load();
    return true;
  }

  /// 从 settings 恢复
  Future<void> load() async {
    final raw = await ref.read(settingsDaoProvider).get(key);
    if (raw != null) state = raw == '1';
  }

  /// 设置并持久化
  Future<void> set(bool value) async {
    state = value;
    await ref.read(settingsDaoProvider).set(key, value ? '1' : '0');
  }
}

/// 播放时自动缓存 Provider
final audioCacheEnabledProvider =
    NotifierProvider<AudioCacheEnabledNotifier, bool>(
        AudioCacheEnabledNotifier.new);

/// 缓存版本号：缓存新增/清空后自增，UI 据此刷新「离线可用」标记
class AudioCacheVersion extends Notifier<int> {
  @override
  int build() => 0;

  /// 缓存变化时调用
  void bump() => state++;
}

/// 缓存版本 Provider
final audioCacheVersionProvider =
    NotifierProvider<AudioCacheVersion, int>(AudioCacheVersion.new);

/// 把缓存实现的变更流接到版本号上（并在启动时建一次索引）
final audioCacheBindingProvider = Provider<void>((ref) {
  final cache = ref.watch(audioCacheProvider);
  unawaited(cache.init());
  final sub = cache.changes.listen((_) {
    ref.read(audioCacheVersionProvider.notifier).bump();
  });
  ref.onDispose(sub.cancel);
}, name: 'audioCacheBindingProvider');

/// 「离线可用」标记：播放缓存命中（已下载的歌由调用方并上 localPath 判断）
final offlineAvailableProvider = Provider.family<bool, String>((ref, songKey) {
  ref.watch(audioCacheVersionProvider);
  // 未注入缓存实现时（纯组件测试 / 预览）按「不可离线」降级，而不是让组件崩掉；
  // 真正需要缓存的地方（设置页占用 / 清空）仍会直接读 audioCacheProvider 并如实报错。
  try {
    return ref.read(audioCacheProvider).isCached(songKey);
  } catch (_) {
    return false;
  }
}, name: 'offlineAvailableProvider');

/// 播放缓存占用（设置页展示用）
final audioCacheSizeProvider = FutureProvider<int>((ref) async {
  ref.watch(audioCacheVersionProvider);
  return ref.read(audioCacheProvider).sizeOnDisk();
}, name: 'audioCacheSizeProvider');

/// 解析「实际要播的地址」：已下载 → 播放缓存 → 源
///
/// 前两者命中时**完全不请求源**（源失效/断网也能播）。回源那一趟顺带把元数据
/// 登记给 enrich 复用，所以一次播放只请求一次详情。
final playSourceResolverProvider = Provider<Future<String> Function(Song)>((ref) {
  return (song) async {
    final cache = ref.read(audioCacheProvider);
    // ① 用户主动下载过的文件
    final downloaded = await cache.downloadedUrlFor(song);
    if (downloaded != null && downloaded.isNotEmpty) return downloaded;
    // ② 播放缓存（离线可用）
    final cached = cache.localUrlFor(song.globalKey);
    if (cached != null) return cached;
    // ③ 回源：顺带拿元数据，登记 + 落库
    final info = await ref
        .read(sourceManagerProvider)
        .getPlayable(song.sourceId, song.id);
    final meta = info.meta;
    if (meta != null) {
      final svc = ref.read(songMetadataServiceProvider);
      svc.rememberDetail(meta); // 供紧随其后的 enrich 复用，避免重复请求详情
      unawaited(svc.enrich(song, detail: meta));
    }
    return info.url;
  };
}, name: 'playSourceResolverProvider');


/// 读缓存里这首歌的最新快照（**必须 watch AsyncValue，而不是 Song 值**）
///
/// 坑在这里：Song 的 == 只比 (id, sourceId)，所以"封面/时长被补齐"这种变化
/// 会被 Riverpod 判成"值没变"，跳过通知 —— 表现在界面上就是：正在播放的那首
/// 封面永远不更新，切到下一首时"上一首的封面"才补显出来（实测到的问题）。
/// songMetaMapProvider 的 AsyncValue 每次解析都是新对象，watch 它才有通知。
Song? _cachedSongMeta(WidgetRef ref, String key) {
  ref.watch(songMetaVersionProvider);
  return ref.watch(songMetaMapProvider).value?[key];
}

/// 曲目展示封面：配表 → 快照 → 元数据缓存（songs 表）
///
/// 规则源（歌曲宝/6U 等）的列表接口不给封面，播过一次后缓存里才有。
/// 不统一走这里就会出现"同一首歌列表有封面、首页卡片没有"的不一致 ——
/// 所以各处一律调这个函数，而不是各自写一遍回落。
String? resolveSongCover(WidgetRef ref, Song song, {String? catalogCover}) {
  final direct = catalogCover ?? song.coverUrl;
  if (direct != null && direct.isNotEmpty) return direct;
  return _cachedSongMeta(ref, song.globalKey)?.coverUrl;
}

/// 曲目展示时长（秒）：快照 → 配表 → 元数据缓存
///
/// 列表接口不给时长时靠播放器实测回写，读的时候统一在这里回落。
int resolveSongDuration(WidgetRef ref, Song song, {int? catalogDuration}) {
  final direct = song.duration;
  if (direct != null && direct > 0) return direct;
  final catalog = catalogDuration;
  if (catalog != null && catalog > 0) return catalog;
  return _cachedSongMeta(ref, song.globalKey)?.duration ?? 0;
}

/// 曲目元数据补齐服务
///
/// 背景：规则源（如 6U）的列表接口不给封面/时长，详情接口给封面但没有时长，
/// 于是列表里长期显示灰块 + 0:00。这里在"取详情"和"播放后拿到真实时长"两个时机
/// 把缺失字段补进 songs 表，展示层再按 globalKey 回落读取。
class SongMetadataService {
  /// Riverpod 引用
  final Ref ref;

  /// 构造
  SongMetadataService(this.ref);

  /// 已写过的标记（key:field），避免同一首歌反复写库
  final Set<String> _written = {};

  /// 最近几次「取播放地址时顺带拿到的详情」，供紧随其后的 enrich 复用
  ///
  /// 播放器解析地址时会走 getPlayable，那一趟已经把封面/歌手拿回来了；
  /// 登记下来后 enrich 就不必为封面再请求一次详情。
  final Map<String, Song> _pendingDetail = {};

  /// 登记「取地址时顺带取回的详情」（最多留 8 条，超出整体清空）
  void rememberDetail(Song detail) {
    if (_pendingDetail.length >= 8) _pendingDetail.clear();
    _pendingDetail[detail.globalKey] = detail;
  }

  /// 用详情补齐封面/标题/歌手（只补空），必要时写库
  ///
  /// 依次合并三种来源，任一环节已经补齐就不再多打一次详情请求：
  ///   ① 调用方给的详情  ② 登记过的详情  ③ 数据库里已有的行
  /// 这样"取地址"和"补封面"共用同一份信息，同一次播放不会请求两次详情。
  Future<Song> enrich(Song song, {Song? detail}) async {
    var merged = song;
    final provided = detail ?? _pendingDetail[song.globalKey];
    final existing = await _loadCached(song);

    // 写库前已知的信息：用来判断"这一趟有没有带来新东西"。
    // 不能因为"字段已经齐了"就提前返回 —— 详情是参数传进来的，
    // 提前返回会把落库也跳掉，封面就永远进不了缓存（被测试抓到的缺陷）。
    final knownCover = existing?.coverUrl ?? song.coverUrl ?? '';
    final knownDuration = existing?.duration ?? song.duration ?? 0;

    if (provided != null) merged = mergeSongMetadata(merged, provided);
    if (existing != null) merged = mergeSongMetadata(merged, existing);

    final needsCover = (merged.coverUrl ?? '').isEmpty;
    // 还缺封面就回源问一次详情（规则源详情通常带封面）
    if (provided == null && needsCover) {
      try {
        final source = ref.read(sourceManagerProvider).getSource(song.sourceId);
        if (source != null) {
          merged = mergeSongMetadata(merged, await source.getSongDetail(song.id));
        }
      } catch (e) {
        SourceLogBus.instance.emit(
            song.sourceId, SourceLogLevel.warn, '元数据', '取详情失败: $e');
      }
    }
    final hasNewInfo = (merged.coverUrl ?? '') != knownCover ||
        (merged.duration ?? 0) != knownDuration;
    if (hasNewInfo) await _persist(merged, 'meta');
    return merged;
  }

  /// 读库里已经写过的行（读失败当"没有"，不影响主流程）
  Future<Song?> _loadCached(Song song) async {
    try {
      return await ref.read(songDaoProvider).getSong(song.id, song.sourceId);
    } catch (_) {
      return null;
    }
  }

  /// 播放器实测时长回写（毫秒 → 秒），仅当原本没有时长
  Future<void> saveDuration(Song song, int milliseconds) async {
    if (milliseconds <= 0) return;
    if ((song.duration ?? 0) > 0) return;
    final seconds = (milliseconds / 1000).round();
    if (seconds <= 0) return;
    await _persist(song.copyWith(duration: seconds), 'duration');
  }

  // ==================== 歌词缓存 ====================

  /// 进行中的歌词请求（按曲目键去重：播放触发与打开歌词页可能同时要）
  final Map<String, Future<Lyrics?>> _lyricInFlight = {};

  /// 确保这首歌的歌词已进缓存，并返回它
  ///
  /// 触发时机是**曲目开始播放时**（不是打开歌词页才请求），所以：
  ///   ① 缓存里已有 → 直接返回，一次远程都不发；
  ///   ② 同一首已有请求在飞 → 复用，不重复请求；
  ///   ③ 否则问源，成功后写进 songs.lyric（下次就能离线看到）。
  Future<Lyrics?> ensureLyrics(Song song) {
    final inFlight = _lyricInFlight[song.globalKey];
    if (inFlight != null) return inFlight;
    final future = _loadOrFetchLyrics(song);
    _lyricInFlight[song.globalKey] = future;
    unawaited(future.whenComplete(() {
      if (identical(_lyricInFlight[song.globalKey], future)) {
        _lyricInFlight.remove(song.globalKey);
      }
    }));
    return future;
  }

  /// 读缓存 → 未命中问源 → 成功落库
  Future<Lyrics?> _loadOrFetchLyrics(Song song) async {
    final cached = await _cachedLyrics(song);
    if (cached != null && cached.lines.isNotEmpty) {
      SourceLogBus.instance.emit(song.sourceId, SourceLogLevel.info, '歌词',
          'id=${song.id} 命中缓存，未请求远程');
      return cached;
    }

    // 源已失效（被删除/停用）时如实返回缓存，可能为 null —— 不造假歌词
    final source = ref.read(sourceManagerProvider).getSource(song.sourceId);
    if (source == null) {
      SourceLogBus.instance.emit(song.sourceId, SourceLogLevel.warn, '歌词',
          'id=${song.id} 源不存在，仅缓存可用');
      return cached;
    }

    try {
      final lyrics =
          await ref.read(sourceManagerProvider).getLyrics(song.sourceId, song.id);
      if (lyrics == null || lyrics.lines.isEmpty) return cached;
      await _persistLyric(song, lyrics);
      return lyrics;
    } catch (e) {
      SourceLogBus.instance.emit(song.sourceId, SourceLogLevel.warn, '歌词',
          'id=${song.id} 取词失败，回落缓存: $e');
      return cached;
    }
  }

  /// 读 songs 表里的歌词缓存
  Future<Lyrics?> _cachedLyrics(Song song) async {
    final row = await _loadCached(song);
    final text = row?.lyric;
    if (text == null || text.trim().isEmpty) return null;
    final isLrc = text.contains('[');
    return Lyrics(
      songId: song.id,
      sourceId: song.sourceId,
      // 与源侧口径一致：没有时间轴时整段作为一行文本，而不是丢弃
      lines: isLrc
          ? LrcParser.parse(text)
          : [LyricLine(time: Duration.zero, text: text)],
      isLrc: isLrc,
    );
  }

  /// 歌词落库（复用 _persist：合并旧行 + 同曲只写一次 + bump）
  Future<void> _persistLyric(Song song, Lyrics lyrics) async {
    await _persist(song.copyWith(lyric: LrcParser.toLrc(lyrics)), 'lyric');
  }

  /// 同一首歌的写库链：把"读旧行 → 合并 → 替换"串起来
  ///
  /// 为什么必须串行：insertSong 是 REPLACE 语义，并发写会各自读到**旧快照**再
  /// 整体覆盖。实测：歌词刚写完，紧接着的 meta 写用陈旧快照把它抹掉了
  /// （真机日志：field=lyric 之后 field=meta，随后歌词缓存又得重新回源）。
  final Map<String, Future<void>> _writeChain = {};

  /// 写库（保留已有的 localPath，避免把"已下载"标记冲掉）
  Future<void> _persist(Song song, String field) {
    final key = '${song.globalKey}:$field';
    if (_written.contains(key)) return Future<void>.value();
    _written.add(key);
    final prev = _writeChain[song.globalKey] ?? Future<void>.value();
    final next = prev.then((_) => _persistNow(song, field));
    _writeChain[song.globalKey] = next;
    return next;
  }

  /// 真正的写入（只在 [_persist] 的串行链里被调用）
  Future<void> _persistNow(Song song, String field) async {
    try {
      final dao = ref.read(songDaoProvider);
      final existing = await dao.getSong(song.id, song.sourceId);
      // insertSong 是 REPLACE 语义：必须先把旧行合并进来，
      // 否则"后写的这次"会用它自己的空字段把已写入的封面/时长冲掉（实测过）。
      final merged = existing == null
          ? song
          : mergeSongMetadata(song, existing).copyWith(
              localPath: song.localPath ?? existing.localPath,
            );
      await dao.insertSong(merged);
      SourceLogBus.instance.emit(song.sourceId, SourceLogLevel.info, '元数据',
          '已写入 songs key=${song.globalKey} field=$field dur=${merged.duration} cover=${(merged.coverUrl ?? '').isNotEmpty}');
      ref.read(songMetaVersionProvider.notifier).bump();
    } catch (e) {
      SourceLogBus.instance.emit(
          song.sourceId, SourceLogLevel.warn, '元数据', '写入失败: $e');
    }
  }
}

/// 元数据补齐服务 Provider
final songMetadataServiceProvider = Provider<SongMetadataService>(
  (ref) => SongMetadataService(ref),
  name: 'songMetadataServiceProvider',
);

/// 播放控制器 Provider
final playbackControllerProvider = Provider<PlaybackController>(
  (ref) => PlaybackController(ref),
  name: 'playbackControllerProvider',
);

// ==================== 沉浸播放页开关 ====================

/// 沉浸播放页展开状态
class NowPlayingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// 展开
  void open() => state = true;

  /// 收起
  void close() => state = false;

  /// 切换
  void toggle() => state = !state;
}

/// 沉浸播放页 Provider
final nowPlayingProvider =
    NotifierProvider<NowPlayingNotifier, bool>(NowPlayingNotifier.new);

/// 歌词视图是否展开
class LyricsOpenNotifier extends Notifier<bool> {
  static const String key = 'lyrics_open';

  @override
  bool build() {
    load();
    return false;
  }

  /// 从 settings 恢复
  Future<void> load() async {
    final raw = await ref.read(settingsDaoProvider).get(key);
    if (raw != null) state = raw == '1';
  }

  /// 切换并持久化
  Future<void> toggle() async {
    state = !state;
    await ref.read(settingsDaoProvider).set(key, state ? '1' : '0');
  }
}

/// 歌词展开 Provider
final lyricsOpenProvider =
    NotifierProvider<LyricsOpenNotifier, bool>(LyricsOpenNotifier.new);

// ==================== 歌词（真实源 + 演示歌词兜底） ====================

/// 当前曲目歌词：先问源，再退回演示歌词（仅演示曲库曲目）
class LyricsNotifier extends Notifier<Lyrics?> {
  @override
  Lyrics? build() {
    final song = ref.watch(currentSongProvider);
    if (song != null) {
      unawaited(_load(song));
    }
    return null;
  }

  Future<void> _load(Song song) async {
    // 统一走元数据服务：缓存优先 + 并发去重 + 成功后落库。
    // 曲目一开始播就已经取过词，所以这里通常只是"读缓存"，不发远程。
    try {
      final lyrics =
          await ref.read(songMetadataServiceProvider).ensureLyrics(song);
      if (ref.read(currentSongProvider)?.globalKey != song.globalKey) return;
      state = (lyrics != null && lyrics.lines.isNotEmpty) ? lyrics : null;
    } catch (_) {
      state = null;
    }
  }
}

/// 歌词 Provider
final lyricsProvider = NotifierProvider<LyricsNotifier, Lyrics?>(LyricsNotifier.new);

// ==================== 音乐源 ====================

/// 已注册的音乐源
final sourceListProvider = FutureProvider<List<MusicSource>>(
  (ref) => ref.watch(sourceManagerProvider).getAllSources(),
  name: 'sourceListProvider',
);

/// 源启用状态（持久化到 settings key = source_enabled_<id>）
class SourceEnabledNotifier extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() {
    final sources = ref.watch(sourceListProvider).value ?? const <MusicSource>[];
    final manager = ref.read(sourceManagerProvider);
    final map = {
      for (final s in sources) s.sourceInfo.id: manager.isSourceEnabled(s.sourceInfo.id),
    };
    unawaited(_restore(map));
    return map;
  }

  /// 恢复持久化的启用状态
  Future<void> _restore(Map<String, bool> map) async {
    final all = await ref.read(settingsDaoProvider).getAll();
    var changed = false;
    for (final entry in all.entries) {
      if (!entry.key.startsWith('source_enabled_')) continue;
      final id = entry.key.substring('source_enabled_'.length);
      if (!map.containsKey(id)) continue;
      final value = entry.value == '1';
      if (map[id] != value) {
        map[id] = value;
        changed = true;
      }
      ref.read(sourceManagerProvider).setSourceEnabled(id, value);
    }
    if (changed) state = {...map};
  }

  /// 切换启用状态
  Future<void> toggle(String sourceId, bool enabled) async {
    ref.read(sourceManagerProvider).setSourceEnabled(sourceId, enabled);
    state = {...state, sourceId: enabled};
    await ref
        .read(settingsDaoProvider)
        .set('source_enabled_$sourceId', enabled ? '1' : '0');
  }
}

/// 源启用状态 Provider
final sourceEnabledProvider =
    NotifierProvider<SourceEnabledNotifier, Map<String, bool>>(
        SourceEnabledNotifier.new);

/// 已启用的源
final enabledSourcesProvider = Provider<List<MusicSource>>((ref) {
  final enabled = ref.watch(sourceEnabledProvider);
  final sources = ref.watch(sourceListProvider).value ?? const <MusicSource>[];
  return sources
      .where((s) => enabled[s.sourceInfo.id] ?? false)
      .toList(growable: false);
}, name: 'enabledSourcesProvider');

/// 推荐歌单（聚合各已启用源的 getPlaylistList，单源失败跳过）
final recommendedPlaylistsProvider = FutureProvider<List<Playlist>>((ref) async {
  final sources = ref.watch(enabledSourcesProvider);
  final out = <Playlist>[];
  for (final source in sources) {
    try {
      final list = await source.getPlaylistList();
      out.addAll(list);
    } catch (_) {
      // 单源失败不影响其它源
    }
  }
  return out;
}, name: 'recommendedPlaylistsProvider');

/// 某个源歌单的歌曲列表
final sourcePlaylistSongsProvider = FutureProvider.family<List<Song>,
    ({String sourceId, String playlistId})>((ref, key) async {
  final source = ref.watch(sourceManagerProvider).getSource(key.sourceId);
  if (source == null) return const [];
  try {
    return await source.getPlaylistSongs(key.playlistId);
  } catch (_) {
    return const [];
  }
}, name: 'sourcePlaylistSongsProvider');

/// 源执行日志（订阅 SourceLogBus，保留最近 200 条）
class SourceLogState {
  /// 日志条目（新→旧）
  final List<SourceLogEntry> entries;

  /// 构造日志状态
  const SourceLogState({this.entries = const []});
}

/// 源日志 Notifier
class SourceLogNotifier extends Notifier<SourceLogState> {
  static const int _maxEntries = 200;

  StreamSubscription<SourceLogEntry>? _sub;

  @override
  SourceLogState build() {
    final initial = SourceLogBus.instance.entries.take(_maxEntries).toList();
    _sub = SourceLogBus.instance.stream.listen((e) {
      state = SourceLogState(
        entries: [e, ...state.entries.take(_maxEntries - 1)],
      );
    });
    ref.onDispose(() => _sub?.cancel());
    return SourceLogState(entries: initial);
  }

  /// 清空日志
  void clear() {
    SourceLogBus.instance.clear();
    state = const SourceLogState();
  }
}

/// 源日志 Provider
final sourceLogProvider =
    NotifierProvider<SourceLogNotifier, SourceLogState>(SourceLogNotifier.new);

// ==================== 扫描与下载 ====================

/// 本地扫描状态
class ScanState {
  /// 是否扫描中
  final bool scanning;

  /// 命中的曲目数
  final int? foundCount;

  /// 失败原因
  final String? error;

  /// 构造扫描状态
  const ScanState({this.scanning = false, this.foundCount, this.error});
}

/// 扫描 Notifier（写 settings 的 scan_dir 后执行扫描）
class ScanNotifier extends Notifier<ScanState> {
  @override
  ScanState build() => const ScanState();

  /// 设置扫描目录
  Future<void> setScanDir(String path) async {
    await ref.read(settingsDaoProvider).set('scan_dir', path);
    ref.invalidate(scanDirProvider);
  }

  /// 执行扫描（读 settings 里的目录），完成后刷新本地曲目
  Future<void> scan() async {
    state = const ScanState(scanning: true);
    try {
      final source = ref.read(localScanSourceProvider);
      if (source == null) {
        state = const ScanState(error: '本地扫描源未注册');
        return;
      }
      final count = await source.scanFromConfig();
      await ref.read(localTracksProvider.notifier).load();
      state = ScanState(scanning: false, foundCount: count);
    } catch (e) {
      state = ScanState(scanning: false, error: '$e');
    }
  }

  /// 直接扫描指定目录
  Future<void> scanDirectory(String path) async {
    state = const ScanState(scanning: true);
    try {
      final source = ref.read(localScanSourceProvider);
      if (source == null) {
        state = const ScanState(error: '本地扫描源未注册');
        return;
      }
      await setScanDir(path);
      final count = await source.scanDirectory(path);
      await ref.read(localTracksProvider.notifier).load();
      state = ScanState(scanning: false, foundCount: count);
    } catch (e) {
      state = ScanState(scanning: false, error: '$e');
    }
  }
}

/// 扫描 Provider
final scanProvider = NotifierProvider<ScanNotifier, ScanState>(ScanNotifier.new);

/// 下载任务流（先发当前快照，再转发实时更新）
final downloadTasksProvider = StreamProvider<List<DownloadTask>>(
  (ref) async* {
    final manager = ref.watch(downloadManagerProvider);
    yield manager.getTasks();
    yield* manager.taskStream;
  },
  name: 'downloadTasksProvider',
);

/// 下载写操作（取消 / 重试 / 删除缓存 / 清理已结束）
class DownloadActions {
  /// Riverpod 引用
  final Ref ref;

  /// 构造写操作
  DownloadActions(this.ref);

  DownloadManager get _manager => ref.read(downloadManagerProvider);

  /// 开始下载一首歌（已缓存时直接返回本地路径）
  Future<String?> download(Song song, {String? url}) =>
      _manager.download(song, url: url);

  /// 取消任务
  Future<void> cancel(String songKey) => _manager.cancel(songKey);

  /// 重新下载
  Future<String?> retry(Song song) => _manager.download(song);

  /// 删除缓存
  Future<void> deleteCache(String songKey) => _manager.deleteCache(songKey);

  /// 某首歌是否已缓存
  Future<bool> isCached(String songKey) => _manager.isCached(songKey);

  /// 清理已结束的任务（返回清理条数）
  Future<int> clearFinished() async {
    final tasks = _manager
        .getTasks()
        .where((t) => t.status != DownloadStatus.downloading)
        .toList();
    for (final task in tasks) {
      await _manager.deleteCache(task.songKey);
    }
    return tasks.length;
  }
}

/// 下载写操作 Provider
final downloadActionsProvider = Provider<DownloadActions>(
  (ref) => DownloadActions(ref),
  name: 'downloadActionsProvider',
);

// ==================== 插件与订阅（薄封装，壳工程注入实例） ====================

/// 插件/订阅管理的注入点
///
/// 具体实现由壳工程提供（file_picker / path_provider 这类平台能力不该被 UI 包直接依赖），
/// 未注入时相关按钮会给出明确提示而不是静默失败。
class PluginHost {
  /// 选择并导入一个插件文件（返回导入后的源名，取消返回 null）
  final Future<String?> Function() importPlugin;

  /// 列举已安装插件（名称 + 来源说明）
  final Future<List<String>> Function() listPlugins;

  /// 构造宿主
  const PluginHost({required this.importPlugin, required this.listPlugins});
}

/// 插件宿主 Provider（默认未注入）
final pluginHostProvider = Provider<PluginHost?>((ref) => null, name: 'pluginHostProvider');

/// 订阅管理的注入点（与 ui 包的 SubscriptionLibrary 对应）
class SubscriptionHost {
  /// 当前订阅数量
  final int Function() count;

  /// 添加订阅（返回是否成功）
  final Future<bool> Function(String url, String type, String? alias) add;

  /// 删除订阅
  final Future<void> Function(String url) remove;

  /// 检查全部订阅更新（返回 (成功数, 失败数)）
  final Future<(int, int)> Function() checkAll;

  /// 构造宿主
  const SubscriptionHost({
    required this.count,
    required this.add,
    required this.remove,
    required this.checkAll,
  });
}

/// 订阅宿主 Provider（默认未注入）
final subscriptionHostProvider =
    Provider<SubscriptionHost?>((ref) => null, name: 'subscriptionHostProvider');
