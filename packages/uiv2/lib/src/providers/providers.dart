/// 状态层 —— 真实数据能力接线（显式 Riverpod Provider，不使用代码生成）。
///
/// 设计原则（对应「不要 mock，用项目已有能力」）：
///   * 服务类 Provider（appDatabase/sourceManager/player/downloadManager/
///     recentPlaysService）由壳工程在 ProviderScope.overrides 注入；
///   * 所有列表数据都来自真实来源：DAO（收藏/歌单/最近播放/设置）、
///     SourceManager（搜索/歌单/专辑/艺人/歌词）、LocalScanSource（本地曲目）、
///     DownloadManager（下载任务）、SourceLogBus（运行日志）；
///   * 演示曲库的真实数据由 Demo Debug 源（demo_source）提供；App 内只保留
///     可注入的展示元数据，没有内置曲目/歌词常量，也没有 mock 数据分支。
library;

import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalog.dart';

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
/// 播放进度 DAO（启动恢复 / 歌单「继续播放」/ 定时落盘共用）
final playProgressDaoProvider = Provider<PlayProgressDao>(
  (ref) => ref.watch(appDatabaseProvider).playProgressDao,
  name: 'playProgressDaoProvider',
);

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

// ==================== 演示曲库展示元数据（可选注入） ====================

/// 曲库展示元数据。
///
/// 默认空：Release 不注入演示目录。Debug 时壳工程把 demo_source 的
/// /catalog.json 解析成 [Catalog] 后 override 这个 Provider。
final catalogProvider = Provider<Catalog>(
  (ref) => Catalog.empty(),
  name: 'catalogProvider',
);

/// 曲目 id → [Song]（仅用于「把展示元数据当候选曲目」的场景）
final catalogSongsProvider = Provider<Map<String, Song>>((ref) {
  final catalog = ref.watch(catalogProvider);
  return {
    for (final track in catalog.tracks)
      track.id: Song(
        id: track.id,
        sourceId: kCatalogSourceId,
        title: track.title,
        artist: track.artist,
        album: track.album,
        coverUrl: track.cover,
        duration: track.duration,
        extra: {
          'genre': track.genre,
          'albumId': track.albumId,
          'no': track.no,
          'local': track.local,
          'downloaded': track.downloaded,
        },
      ),
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
  for (final song in ref.watch(queueProvider).songs) {
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

  /// 从最近播放里移除一条（只删记录，不动缓存/收藏/歌单）
  Future<void> remove(String songKey) async {
    await ref.read(recentPlaysServiceProvider).remove(songKey);
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
    // 歌单没了，它的播放进度也没有意义（否则会留下永远恢复不了的行）
    await ref.read(playProgressDaoProvider).delete(PlayQueueKind.playlist.name, id);
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
    // 同上：收藏歌单的进度也要一起清掉
    await ref.read(playProgressDaoProvider).delete(PlayQueueKind.playlist.name, playlistId);
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

// ==================== 启动恢复（上次的队列 + 曲目 + 进度） ====================

/// 按队列身份重建曲目（不存队列内容，只按真实数据重建）
///
/// 四类队列都能从数据库推导，所以 play_progress 只存"听到哪"就够了；
/// 存了队列内容反而会与真实数据不一致（歌单删了歌，队列里还留着）。
Future<List<Song>> songsOfQueueIdentity(
  Ref ref,
  PlayQueueKind kind,
  String? id,
) async {
  switch (kind) {
    case PlayQueueKind.recent:
      // 冷启动时 RecentNotifier 还是空的（build 返回 []、异步 load 才填）。
      // 不等它加载完就取，会误判"这个队列没有曲目"——真机实测：上次听的是最近播放，
      // 结果恢复时读到空列表，把进度当成废数据删掉了。
      await ref.read(recentProvider.notifier).load();
      return ref.read(recentSongsProvider);
    case PlayQueueKind.liked:
      await ref.read(likedProvider.notifier).load();
      return ref.read(likedSongsProvider);
    case PlayQueueKind.local:
      await ref.read(localTracksProvider.notifier).load();
      return ref.read(localTracksProvider);
    case PlayQueueKind.playlist:
      if (id == null || id.isEmpty) return const [];
      return ref.read(playlistSongsProvider(id).future);
  }
}

/// 队列标题（按身份取真实名字，歌单改名后恢复出来的标题也是新的）
Future<String> titleOfQueueIdentity(Ref ref, PlayQueueKind kind, String? id) async {
  switch (kind) {
    case PlayQueueKind.recent:
      return '最近播放';
    case PlayQueueKind.liked:
      return '我喜欢的音乐';
    case PlayQueueKind.local:
      return '本地音乐';
    case PlayQueueKind.playlist:
      if (id == null || id.isEmpty) return '歌单';
      final p = await ref.read(playlistByIdProvider(id).future);
      return p?.name ?? '歌单';
  }
}

/// 某歌单上次的播放进度（歌单详情头部的主按钮据此决定「播放」还是「继续播放」）
final playlistProgressProvider =
    FutureProvider.family<PlayProgress?, String>((ref, playlistId) {
  return ref
      .read(playProgressDaoProvider)
      .get(PlayQueueKind.playlist.name, playlistId);
}, name: 'playlistProgressProvider');

/// 启动恢复：把上次的队列、曲目、进度装回播放器（**暂停着，不出声**）
///
/// 只在 AppShell 挂载时跑一次。为什么不用"退出时保存"：桌面端关窗/杀进程
/// 不保证收到回调；进度是边播边写的，所以这里只需要读。
final startupResumeProvider = FutureProvider<void>((ref) async {
  try {
    await runStartupResume(ref);
  } catch (e) {
    // 恢复失败绝不能影响 App 启动，但必须留痕：否则界面就是"什么都没发生"
    SourceLogBus.instance.emit('player', SourceLogLevel.warn, '播放',
        '启动恢复失败: ' + e.toString());
  }
});

/// 启动恢复的实际步骤（抽出来便于重跑与测试）
Future<void> runStartupResume(Ref ref) async {
  final List<PlayProgress> rows;
  try {
    rows = await ref.read(playProgressDaoProvider).getAll();
  } catch (e) {
    SourceLogBus.instance.emit('player', SourceLogLevel.warn, '播放',
        '读播放进度失败: ' + e.toString());
    return;
  }
  if (rows.isEmpty) {
    SourceLogBus.instance.emit(
        'player', SourceLogLevel.info, '播放', '启动恢复：没有进度记录，跳过');
    return;
  }

  // 上次活跃队列：以 settings 里显式记下的指针为准；
  // 没有指针（老版本升级上来）才退回"最近更新的那一行"。
  final pointer = await ref.read(settingsDaoProvider).get(
        QueueNotifier.lastQueueKey,
      );
  PlayProgress? picked;
  if (pointer != null && pointer.isNotEmpty) {
    final cut = pointer.indexOf(':');
    final pKind = cut < 0 ? pointer : pointer.substring(0, cut);
    final pId = cut < 0 ? '' : pointer.substring(cut + 1);
    for (final r in rows) {
      if (r.queueKind == pKind && r.queueId == pId) picked = r;
    }
  }
  final row = picked ?? rows.first;
  SourceLogBus.instance.emit('player', SourceLogLevel.info, '播放',
      '启动恢复：' + rows.length.toString() + ' 条进度，按' +
          (picked == null ? '时间戳' : '指针 ' + pointer!) + ' 选中 ' +
          row.identity + ' / ' + row.songKey);
  PlayQueueKind? kind;
  for (final k in PlayQueueKind.values) {
    if (k.name == row.queueKind) kind = k;
  }
  if (kind == null) {
    SourceLogBus.instance.emit('player', SourceLogLevel.warn, '播放',
        '启动恢复：未知队列种类 ' + row.queueKind + '，跳过');
    return;
  }
  final id = row.queueId.isEmpty ? null : row.queueId;

  final songs = await songsOfQueueIdentity(ref, kind, id);
  if (songs.isEmpty) {
    // 只有"确实不存在了"才清进度（歌单被删）。曲目暂时为空可能只是还没加载完，
    // 清掉就等于把用户上次听到哪弄丢了 —— 宁可留着下次再试。
    var gone = false;
    if (kind == PlayQueueKind.playlist && id != null) {
      gone = await ref.read(playlistByIdProvider(id).future) == null;
    }
    if (gone) {
      SourceLogBus.instance.emit('player', SourceLogLevel.warn, '播放',
          '启动恢复：歌单 ' + (id ?? '') + ' 已不存在，清掉进度');
      await ref.read(playProgressDaoProvider).delete(row.queueKind, row.queueId);
    } else {
      SourceLogBus.instance.emit('player', SourceLogLevel.warn, '播放',
          '启动恢复：「' + row.identity + '」暂时取不到曲目，保留进度下次再试');
    }
    return;
  }

  final index = songs.indexWhere((s) => s.globalKey == row.songKey);
  if (index < 0) {
    // 那首歌已不在这个队列里：整体恢复队列，但不假装有进度
    SourceLogBus.instance.emit('player', SourceLogLevel.warn, '播放',
        '启动恢复：' + row.songKey + ' 不在「' + row.identity + '」的 ' +
            songs.length.toString() + ' 首里，跳过');
    return;
  }

  final title = await titleOfQueueIdentity(ref, kind, id);
  final queue = PlayQueue(kind: kind, id: id, title: title, songs: songs);
  final position = Duration(milliseconds: row.positionMs);
  var ok = await ref
      .read(playbackControllerProvider)
      .prepareQueue(queue, index, position);
  if (!ok) {
    // 冷启动时源站/缓存可能还没就绪（真机实测：偶发一次拿不到地址）。
    // 恢复"上次听到哪"是用户明确要的，值得再等 2 秒重试一次。
    await Future<void>.delayed(const Duration(seconds: 2));
    ok = await ref
        .read(playbackControllerProvider)
        .prepareQueue(queue, index, position);
  }
  if (!ok) return;
  SourceLogBus.instance.emit('player', SourceLogLevel.info, '播放',
      '已恢复上次队列「' + title + '」第 ' + (index + 1).toString() + ' 首，进度 ' +
          (row.positionMs ~/ 1000).toString() + 's（暂停中）');
}

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

  /// 该来源的命中歌曲（loading 阶段为空）
  final List<Song> songs;

  /// 该来源是否还在搜（tab 上要显示 loading，结果区要忽略它）
  final bool loading;

  /// 该来源是否还有下一页
  final bool hasMore;

  /// 构造来源分组
  const SearchPool({
    required this.id,
    required this.name,
    required this.songs,
    this.loading = false,
    this.hasMore = false,
  });
}

/// 搜索状态
class SearchState {
  /// 关键词
  final String keyword;

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

  /// 命中总数 —— **实时算出来**，不再是单独存的字段。
  ///
  /// 历史 bug（用户报「结果明明有了却显示没有找到、tab 还消失」）：total 原来只在
  /// 搜索**全部结束**时写一次，而 UI 的空态判断读的就是它 —— 于是「第一个源刚回来、
  /// 结果已上屏」的那段窗口里 total 仍是 0：界面显示「没有找到」、来源条一并消失，
  /// 等所有源都结束 total 才被写上，结果「一下子全冒出来」。
  int get total => filteredTotal;

  /// 参与筛选的分组（**不含还在 loading 的分组** —— 它们还没有歌曲，
  /// 会让「来自 N 个源」这类计数多算，也会让空结果文案提前出现）
  List<SearchPool> get activePools {
    final done = pools.where((p) => !p.loading);
    return sourceFilter == 'all'
        ? done.toList()
        : done.where((p) => p.id == sourceFilter).toList();
  }

  /// 是否还有来源在搜（tab 上的 loading 指示由它控制）
  bool get anyLoading => pools.any((p) => p.loading);

  /// 复制并覆盖字段
  SearchState copyWith({
    String? keyword,
    List<SearchPool>? pools,
    String? sourceFilter,
    bool? expanded,
    bool? loading,
    bool? hasMore,
  }) =>
      SearchState(
        keyword: keyword ?? this.keyword,
        pools: pools ?? this.pools,
        sourceFilter: sourceFilter ?? this.sourceFilter,
        expanded: expanded ?? this.expanded,
        loading: loading ?? this.loading,
        hasMore: hasMore ?? this.hasMore,
      );
}

/// 搜索 Notifier —— 走 [SourceManager.searchStream] 的逐源渐进聚合搜索
class SearchNotifier extends Notifier<SearchState> {
  @override
  SearchState build() => const SearchState();

  /// 请求令牌：只有最后一次搜索允许写回 state
  ///
  /// 为什么必须有：并发搜索时**谁最后返回谁写 state**。用户遇到的
  /// 「输入框是『周杰伦』、结果是『周』的」就是这个竞态 —— 先发的短词
  /// 后返回，把新结果覆盖掉了。光加长防抖治不了本（回车、点历史词、
  /// 快速输入都还能撞上），所以过期请求的结果一律丢弃。
  int _token = 0;

  /// 执行搜索（静默失败：单源异常不会打断整体）
  ///
  /// 逐源消费 [SourceManager.searchStream]：先把所有已启用源按默认顺序摆成
  /// loading 占位，谁先回来谁先上屏（已完成区按返回顺序排在前面），
  /// 没有结果的源直接移除 —— 不等所有源都返回。
  Future<void> search(String keyword, {bool recordHistory = false}) async {
    final q = keyword.trim();
    if (recordHistory) {
      await ref.read(searchHistoryProvider.notifier).add(q);
    }
    final token = ++_token;
    if (q.isEmpty) {
      state = const SearchState();
      return;
    }
    final manager = ref.read(sourceManagerProvider);
    state = SearchState(
      keyword: q,
      loading: true,
      pools: [
        for (final s in manager.getEnabledSources())
          SearchPool(
            id: s.sourceInfo.id,
            name: s.sourceInfo.name,
            songs: const [],
            loading: true,
          ),
      ],
    );

    await for (final r in manager.searchStream(keyword: q)) {
      if (token != _token) return; // 过期请求：后面的结果一律不写回
      final name = manager.getSource(r.sourceId)?.sourceInfo.name ?? r.sourceId;
      final slots = [...state.pools];
      final idx = slots.indexWhere((p) => p.id == r.sourceId);
      if (idx >= 0) slots.removeAt(idx);
      if (r.songs.isEmpty) {
        // 没有结果的源：tab 自己消失（不占位）
      } else {
        // 已完成的数量就是插入点：先返回的排在前面，后面仍是未返回源的默认顺序
        final done = slots.where((p) => !p.loading).length;
        slots.insert(
          done,
          SearchPool(
            id: r.sourceId,
            name: name,
            songs: r.songs,
            hasMore: r.hasMore,
          ),
        );
      }
      state = state.copyWith(pools: slots, sourceFilter: _keepFilter(slots));
    }

    if (token != _token) return;
    state = state.copyWith(
      loading: false,
      hasMore: state.pools.any((p) => p.hasMore),
    );
  }

  /// 筛选中的源若已无结果（被移除），筛选自动回到「全部来源」，
  /// 否则会出现「选中一个已经不存在的 tab」的空窗
  String _keepFilter(List<SearchPool> slots) {
    final f = state.sourceFilter;
    if (f == 'all') return f;
    return slots.any((p) => p.id == f) ? f : 'all';
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
/// 播放队列的种类
enum PlayQueueKind {
  /// 最近播放（点搜索候选/首页单曲等"非列表"入口都进这里）
  recent,

  /// 歌单（自建 / 远程收藏 / 我喜欢 都各自是一张歌单式队列）
  playlist,

  /// 我喜欢的音乐
  liked,

  /// 本地音乐
  local,
}

/// 一个播放队列
///
/// 规则（用户定）：所有播放都发生在某个队列里 —— 当一首歌在播时它必然属于
/// 某个队列；上一首/下一首/播放模式都跟队列走。所以队列不能只是一串曲目，
/// 还必须知道**它来自哪**（哪一类、哪一张、叫什么），列表页点行时才谈得上
/// "成功起播后把当前队列换成它"。
class PlayQueue {
  /// 队列种类
  final PlayQueueKind kind;

  /// 歌单 id（[PlayQueueKind.playlist] 用）
  final String? id;

  /// 展示名：「默认1」「最近播放」「我喜欢的音乐」「本地音乐」
  final String title;

  /// 队列曲目
  final List<Song> songs;

  /// 构造
  const PlayQueue({
    required this.kind,
    required this.title,
    this.id,
    this.songs = const [],
  });

  /// 身份（kind 或 kind:id）—— 用于"这一行是不是当前队列里的歌"的比对
  String get identity =>
      (id == null || id!.isEmpty) ? kind.name : kind.name + ':' + id!;

  /// 是否为空
  bool get isEmpty => songs.isEmpty;

  /// 曲目数
  int get length => songs.length;

  /// 是否允许在队列面板里编辑（拖拽/移除/清空）
  ///
  /// 歌单即队列：编辑队列就等于编辑歌单（删一首真的会把歌单里的歌删掉），
  /// 风险太大 —— 因此**歌单类队列只读**；只有最近播放可以编辑。
  bool get editable => kind == PlayQueueKind.recent;

  /// 复制（改标题或曲目，身份不变）
  PlayQueue copyWith({String? title, List<Song>? songs}) => PlayQueue(
        kind: kind,
        id: id,
        title: title ?? this.title,
        songs: songs ?? this.songs,
      );

  @override
  String toString() => 'PlayQueue(' + kind.name + ', ' + title + ', ' +
      songs.length.toString() + ' 首)';
}

class QueueNotifier extends Notifier<PlayQueue> {
  @override
  PlayQueue build() => const PlayQueue(
        kind: PlayQueueKind.recent,
        title: '最近播放',
      );

  /// settings 里记"上次活跃队列"的键（形如 playlist:xxx / recent / liked / local）
  static const String lastQueueKey = 'last_queue';

  /// 换队列（**只在起播成功后**由 PlaybackController.playInQueue 调用）
  ///
  /// 同时把"上次活跃队列"写进 settings：靠 play_progress 的 updated_at 去猜
  /// 哪个是上次队列并不可靠（任何一次落盘都会刷新时间戳，实测队列会在
  /// 默认1 与最近播放之间来回漂），所以这里显式记死。
  void setQueue(PlayQueue next) {
    state = next;
    unawaited(ref.read(settingsDaoProvider).set(
          lastQueueKey,
          next.id == null || next.id!.isEmpty
              ? next.kind.name
              : next.kind.name + ':' + next.id!,
        ));
  }

  /// 只同步曲目（播放器队列跟随变化：面板编辑、自动续播等）
  ///
  /// 曲目顺序完全一致时**不写 state**：否则每次换曲都会白白重建队列面板。
  void setSongs(List<Song> songs) {
    if (songs.length == state.songs.length) {
      var same = true;
      for (var i = 0; i < songs.length; i++) {
        if (songs[i].globalKey != state.songs[i].globalKey) {
          same = false;
          break;
        }
      }
      if (same) return;
    }
    state = state.copyWith(songs: songs);
  }

  /// 追加到队尾（队列身份不变）
  void append(Song song) => state = state.copyWith(songs: [...state.songs, song]);

  /// 插入到指定下标
  void insertAt(int index, Song song) {
    final next = List.of(state.songs);
    next.insert(index.clamp(0, next.length), song);
    state = state.copyWith(songs: next);
  }

  /// 移除指定下标（返回被移除的歌曲）
  Song? removeAt(int index) {
    if (index < 0 || index >= state.songs.length) return null;
    final next = List.of(state.songs);
    final removed = next.removeAt(index);
    state = state.copyWith(songs: next);
    return removed;
  }

  /// 移动到新下标
  void move(int from, int to) {
    if (from < 0 || from >= state.songs.length) return;
    final next = List.of(state.songs);
    final moving = next.removeAt(from);
    next.insert(to.clamp(0, next.length), moving);
    state = state.copyWith(songs: next);
  }

  /// 某首歌是否在队列里
  bool containsKey(String songKey) =>
      state.songs.any((s) => s.globalKey == songKey);
}

/// 队列 Provider
final queueProvider = NotifierProvider<QueueNotifier, PlayQueue>(QueueNotifier.new);

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

  /// 进入随机播放前的循环模式；退出随机时回到它
  ///
  /// 只在内存里记：重启后若持久化的就是 shuffle，并没有「上一个模式」可恢复，
  /// 此时退回列表循环 —— 刻意不为此再加一个 settings key。
  PlayMode _loopModeBefore = PlayMode.listLoop;

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

  /// 开启/关闭随机播放
  ///
  /// 随机不是独立开关，而是 [PlayMode] 的一个取值 —— 单一事实来源就是播放模式。
  /// 开启时先记下当前的循环模式，关闭时回到它。
  Future<void> setShuffle(bool value) async {
    if (!value) {
      await set(state == PlayMode.shuffle ? _loopModeBefore : state);
      return;
    }
    if (state != PlayMode.shuffle) _loopModeBefore = state;
    await set(PlayMode.shuffle);
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

/// 随机播放开关 —— **派生值**，单一事实来源是 [playModeProvider]。
///
/// 历史问题（用户报「随机播放没生效」）：这里原本是独立的 ShuffleNotifier
/// （settings key = play_shuffle），它的 set/toggle 只写自己的 bool、**从不同步给播放器**；
/// 而 PlayModeNotifier.cycle() 又主动跳过 shuffle，于是 uiv2 里没有任何路径能把
/// PlayMode.shuffle 交给播放器 —— 播放条上的随机按钮看着是开的、实际一直在顺序播放。
/// 现在随机就是播放模式的一个取值，这个开关只是它的视图（只读）。
final shuffleProvider = Provider<bool>(
  (ref) => ref.watch(playModeProvider) == PlayMode.shuffle,
);

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

/// 生命周期哨兵：App 被挂起/隐藏/关闭时立刻落盘
///
/// 为什么需要：桌面端点关闭按钮不保证给我们"退出前"的回调，
/// 进度是边播边写的（5 秒节流），这里再补一次"离开时"的即时保存。
class _ProgressLifecycleFlusher with WidgetsBindingObserver {
  _ProgressLifecycleFlusher(this.ref);

  final Ref ref;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(ref.read(playbackControllerProvider).flushProgressNow());
    }
  }
}

/// 播放器事件流绑定 —— 在 AppShell 顶层 watch 一次即可保持存活
final playerStreamBindingProvider = Provider<void>((ref) {
  final player = ref.watch(playerProvider);
  // 离开 App 前保存进度（测试环境没有 WidgetsBinding 时跳过）
  try {
    final flusher = _ProgressLifecycleFlusher(ref);
    WidgetsBinding.instance.addObserver(flusher);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(flusher));
  } catch (_) {
    // 非 Flutter 绑定环境：忽略
  }
  final subs = <StreamSubscription<dynamic>>[
    player.stateStream.listen((s) {
      ref.read(isPlayingProvider.notifier).set(s == PlayerState.playing);
    }),
    player.positionStream.listen((ms) {
      ref.read(positionProvider.notifier).set(Duration(milliseconds: ms));
      // 进度落库（内部节流）：App 被关掉也不会丢掉"听到哪"
      ref.read(playbackControllerProvider).onPositionTick(ms);
    }),
    player.durationStream.listen((ms) {
      ref.read(durationProvider.notifier).set(Duration(milliseconds: ms));
      // 播放器实测时长回写：列表里 0:00 的曲目播一次就有真实时长了。
      // durationStream 往往早于 currentTrackId 落地，不能只信 currentSongProvider：
      // 那样会把“正在装载的新曲”时长写到上一首。播放器在 _doPlayIndex 一开始就
      // 把 currentIndex 指向新曲，所以优先认队列里正在装载的那一首。
      final player = ref.read(playerProvider);
      Song? song;
      final index = player.currentIndex;
      if (index >= 0 && index < player.queue.length) {
        song = player.queue[index];
      }
      song ??= ref.read(currentSongProvider) ?? player.currentSong;
      if (song != null) {
        unawaited(ref.read(songMetadataServiceProvider).saveDuration(song, ms));
      }
    }),
  ];
  // 唯一同步点：当前曲目只认播放器广播。点播 / 上一首 / 下一首 / 自动续播 / 跳播
  // 最终都会走到播放器的 _playIndex，因此页面显示不可能与正在播放的东西脱节。
  if (player is CurrentSongSource) {
    subs.add((player as CurrentSongSource).currentSongStream.listen((song) {
      // 换曲之前先把上一首的进度写下去（否则只有"最后播的那首"有进度）
      ref.read(playbackControllerProvider).onSongChanged(song?.globalKey);
      ref.read(currentTrackIdProvider.notifier).set(song?.globalKey);
      // 同时留住完整对象：换队列后"在播的那首"可能不在队列里，
      // 只有 id 就会退化成「标题=id」的占位（真机：播放条标题显示成 "2"）
      ref.read(playerCurrentSongProvider.notifier).set(song);
      ref.read(queueProvider.notifier).setSongs(player.queue);
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

  /// 播放一首歌：解析播放地址 → 播放 → 同步 UI 状态 → 记录最近播放。
  ///
  /// 返回值表示是否**真的开始播放**：源没给播放地址（例如演示曲库）时返回 false，
  /// 调用方据此提示用户，而不是让界面假装在播（核心注释明确 getSongUrl 可能为空串）。
  Future<bool> playSong(Song song,
      {String? captchaCode, String? captchaKey}) async {
    final pending = ref.read(pendingProvider.notifier);
    pending.set(song.globalKey);
    try {
      // 统一走「实际要播的地址」解析：已下载 → 播放缓存 → 源。
      // 前两者命中时完全不请求源（源失效/断网也能播）；回源那一趟顺带登记的
      // 元数据由下面的 enrich 复用，所以一次播放只请求一次详情。
      final res = await ref.read(playSourceResolverProvider)(
        song,
        captchaCode: captchaCode,
        captchaKey: captchaKey,
      );
      // 源站要求人机验证：这不是"失败"，挂起挑战等用户输入验证码
      // （旧实现把它当"没地址"，用户只看到含混的"无法播放"）
      if (res.needsChallenge) {
        SourceLogBus.instance.emit(song.sourceId, SourceLogLevel.warn, '播放',
            'id=${song.id} 源站要求人机验证，等待用户输入验证码');
        ref
            .read(pendingCaptchaProvider.notifier)
            .set(PendingCaptcha(song, res.challenge!));
        pending.set(null);
        return false;
      }
      final url = res.url;
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
      await _startPlayback(song, url);
      // pending 由 PlayerImpl._ensureProgressing 保证：真机慢资源时它会等到
      // 首次真实进度（最长 networkLoadTimeout）才让 play() 返回；失败则抛错由
      // 上面 catch 清 pending，item loading 不会提前消失也不会永远挂着。
      pending.set(null);
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

  /// 起播（地址已解析好）：播放器 + 元数据 + 各处状态一起更新
  ///
  /// 抽出来给两条路径共用：正常点播，以及"用户过了人机验证之后"继续播。
  Future<void> _startPlayback(Song song, String url) async {
    final playable = song.copyWith(playUrl: url);
    await _player.play(playable);
    // 封面等元数据异步补齐：不阻塞起播，失败静默
    // （详情已在解析地址时登记，这里不会重复请求）
    unawaited(ref.read(songMetadataServiceProvider).enrich(playable));
    ref.read(currentTrackIdProvider.notifier).set(playable.globalKey);
    ref.read(isPlayingProvider.notifier).set(true);
    // 队列身份与曲目由 playInQueue（起播成功后）负责，这里不再写队列
    await ref.read(recentProvider.notifier).record(playable);
  }

  /// 用户提交验证码
  ///
  /// 为什么不用 [playSong] 重播：验证码错误时源站会再回一次挑战，
  /// 而 [playSong] 会把挑战写回 [pendingCaptchaProvider] → 面板监听者
  /// 再弹一次 → 面板叠面板。这里直接返回结果，由面板**就地**换图重试。
  Future<CaptchaSubmitResult> submitCaptcha(String code) async {
    final pc = ref.read(pendingCaptchaProvider);
    if (pc == null) return const CaptchaSubmitResult(ok: false);
    final res = await ref.read(playSourceResolverProvider)(
      pc.song,
      captchaCode: code,
      captchaKey: pc.challenge.key,
    );
    final challenge = res.challenge;
    if (challenge != null) {
      // 验证码不对（或源站换了新图）：就地更新，不重新挂起、不叠面板
      return CaptchaSubmitResult(ok: false, challenge: challenge);
    }
    if (res.url.isEmpty) return const CaptchaSubmitResult(ok: false);
    await _startPlayback(pc.song, res.url);
    ref.read(pendingCaptchaProvider.notifier).set(null);
    return const CaptchaSubmitResult(ok: true);
  }

  /// 换一张：重新向源站要一次挑战（新的验证图与 key）
  ///
  /// 刻意**不写回** [pendingCaptchaProvider]：面板自己持有当前挑战，
  /// 写回会触发监听者再弹一个面板（叠面板）。
  Future<PlaybackChallenge?> refreshCaptcha() async {
    final pc = ref.read(pendingCaptchaProvider);
    if (pc == null) return null;
    final res = await ref.read(playSourceResolverProvider)(pc.song);
    return res.challenge;
  }

  /// 用户取消验证（不放行播放，但界面明确告知原因）
  void cancelCaptcha() {
    ref.read(pendingCaptchaProvider.notifier).set(null);
  }

  /// **切换队列并播放（唯一入口）**
  ///
  /// 纪律：起播**成功后**才把当前队列换成 [queue] —— 否则点一首播不出来的歌，
  /// 会连"在播的那首属于哪个队列"一起搞错（与之前修过的"失败不该动在播曲目"
  /// 同源）。失败时把播放器队列恢复成原队列，保证在播的歌始终在它自己的队列里。
  Future<bool> playInQueue(PlayQueue queue, {int startIndex = 0}) async {
    if (queue.isEmpty) return false;
    final i = startIndex.clamp(0, queue.length - 1);
    // 换队列前把旧队列的进度落盘（同一队列重复点时也算一次立即保存）
    await _flushProgress(force: true);
    final previous = ref.read(queueProvider);
    _player.setQueue(queue.songs);
    final started = await playSong(queue.songs[i]);
    if (!started) {
      _player.setQueue(previous.songs);
      return false;
    }
    ref.read(queueProvider.notifier).setQueue(queue);
    return true;
  }

  /// 随机播放一个队列：打乱交给播放器的随机模式，**队列身份不变**
  Future<bool> shuffleInQueue(PlayQueue queue) async {
    if (queue.isEmpty) return false;
    // 随机交给播放模式（播放器据此决定下一首），队列身份不变
    await ref.read(playModeProvider.notifier).setShuffle(true);
    return playInQueue(queue);
  }

  // ---------- 播放进度持久化 ----------

  /// 进度写盘节流：至少间隔这么久
  static const Duration _progressInterval = Duration(seconds: 5);

  /// 进度写盘节流：位置至少变了这么多
  static const int _progressMinDeltaMs = 3000;

  /// 结尾这么多毫秒内视为"听完了"，下次从头开始
  static const int _progressEndGuardMs = 3000;

  /// 待落盘的进度快照：哪个队列的哪一首、听到哪
  PlayQueue? _progressQueue;
  String? _progressSongKey;
  int _progressMs = 0;

  /// 上次真正写盘的时刻与位置（节流用）
  DateTime? _lastWriteAt;
  int _lastWriteMs = 0;

  /// 进度流每来一次都会调到这里（节流后再落盘）
  ///
  /// 为什么不"退出时保存"：桌面端关窗/杀进程都不保证收到回调，
  /// 只有边播边写才靠得住。
  void onPositionTick(int ms) {
    final queue = ref.read(queueProvider);
    if (queue.isEmpty) return;
    // 优先用"在播的那一首"；退回可选契约（不实现它的播放器就拿不到，跳过保存）
    final song = ref.read(playerCurrentSongProvider) ??
        (_player is AudibleSongSource
            ? (_player as AudibleSongSource).audibleSong
            : null);
    if (song == null) return;
    _progressQueue = queue;
    _progressSongKey = song.globalKey;
    _progressMs = ms;

    final last = _lastWriteAt;
    if (last != null) {
      if (DateTime.now().difference(last) < _progressInterval) return;
      if ((ms - _lastWriteMs).abs() < _progressMinDeltaMs) return;
    }
    unawaited(_flushProgress());
  }

  /// 曲目切换：先把上一首的进度写下去，再把快照指向新曲
  void onSongChanged(String? newKey) {
    if (_progressSongKey != null && _progressSongKey != newKey) {
      unawaited(_flushProgress(force: true));
    }
    _progressSongKey = newKey;
    _progressMs = 0;
  }

  /// 立刻把当前进度落盘（切队列 / 暂停 / 离开 App 都会调）
  ///
  /// 用播放器的**实时位置**而不是上次 tick 的值：切队列这类时刻必须准，
  /// 否则会少记最多一个 tick 间隔（真机上表现为"进度比听到的少一点"）。
  Future<void> flushProgressNow() => _flushProgress(force: true);

  /// 把当前快照写进 play_progress
  Future<void> _flushProgress({bool force = false}) async {
    final queue = _progressQueue;
    final key = _progressSongKey;
    if (queue == null || key == null) return;
    // 空队列没什么可记；曲目不在这个队列里也说明快照过期了 ——
    // 写了就会产出一条假进度，还会把"上次活跃队列"抢走（真机实测踩过）。
    if (queue.isEmpty || !queue.songs.any((s) => s.globalKey == key)) return;

    // 正在播的就是快照里那首时，以播放器的实时位置为准
    final audible = _player is AudibleSongSource
        ? (_player as AudibleSongSource).audibleSong
        : null;
    var position = _progressMs;
    if (audible != null && audible.globalKey == key) {
      try {
        final live = _player.currentPosition;
        if (live > 0) position = live;
      } catch (_) {
        // 播放器实现读不到实时位置时退回上次 tick 的值，不影响落盘
      }
    }
    if (position < 0) position = 0;
    // 播到结尾附近 → 记 0：下次进这个队列从头开始，而不是"一进去就结束"
    final total = ref.read(durationProvider).inMilliseconds;
    if (total > 0 && position >= total - _progressEndGuardMs) position = 0;

    _lastWriteAt = DateTime.now();
    _lastWriteMs = _progressMs;
    try {
      await ref.read(playProgressDaoProvider).upsert(PlayProgress(
            queueKind: queue.kind.name,
            queueId: queue.id ?? '',
            songKey: key,
            positionMs: position,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ));
    } catch (e) {
      // 落盘失败不该影响播放
      SourceLogBus.instance.emit(
          'player', SourceLogLevel.warn, '播放', '保存播放进度失败: $e');
    }
  }

  /// 读某个队列上次听到哪（歌单详情「继续播放」用它决定要不要提示进度）
  Future<PlayProgress?> savedProgress(PlayQueue queue) =>
      ref.read(playProgressDaoProvider).get(queue.kind.name, queue.id ?? '');

  /// **从该队列上次的位置继续播放**（无记录则等同从头播）
  Future<bool> resumeInQueue(PlayQueue queue) async {
    if (queue.isEmpty) return false;
    var index = 0;
    var position = Duration.zero;
    final saved = await savedProgress(queue);
    if (saved != null) {
      final i = queue.songs.indexWhere((s) => s.globalKey == saved.songKey);
      if (i >= 0) {
        index = i;
        position = Duration(milliseconds: saved.positionMs);
      }
    }
    final started = await playInQueue(queue, startIndex: index);
    if (started && position > Duration.zero) {
      await _player.seek(position);
      ref.read(positionProvider.notifier).set(position);
    }
    return started;
  }

  /// **预置**一个队列的某一首到指定进度（不播放）—— 启动恢复用
  ///
  /// 纪律同 playInQueue：只有底层真的把这个音源装上了，才把当前队列换过去。
  /// 装不上（源没给地址）就恢复原队列，播放条不会显示一首其实没装好的歌。
  Future<bool> prepareQueue(
    PlayQueue queue,
    int index,
    Duration position,
  ) async {
    if (queue.isEmpty) return false;
    final i = index.clamp(0, queue.length - 1);
    final target = queue.songs[i];
    // 换队列前先把当前队列的进度存下来（用户明确要求）
    await _flushProgress(force: true);
    final previous = ref.read(queueProvider);
    _player.setQueue(queue.songs);
    await _player.prepareAt(i, position: position);

    final loaded = _player is AudibleSongSource
        ? (_player as AudibleSongSource).audibleSong
        : null;
    if (loaded == null || loaded.globalKey != target.globalKey) {
      _player.setQueue(previous.songs);
      ref.read(queueProvider.notifier).setQueue(previous);
      SourceLogBus.instance.emit('player', SourceLogLevel.warn, '播放',
          '预置失败（源没给地址？）：' + target.title + '，已回退原队列');
      return false;
    }

    ref.read(queueProvider.notifier).setQueue(queue);
    // 让进度条立刻显示恢复到的位置（暂停中不会有进度事件）
    _progressQueue = queue;
    _progressSongKey = target.globalKey;
    _progressMs = position.inMilliseconds;
    _lastWriteMs = _progressMs;
    ref.read(positionProvider.notifier).set(position);
    ref.read(currentTrackIdProvider.notifier).set(target.globalKey);
    ref.read(isPlayingProvider.notifier).set(false);
    return true;
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
      // 暂停是最常见的"我要走了"信号：立刻落盘，不等节流
      await _flushProgress(force: true);
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

  /// 定位到指定毫秒（续播用：与进度条拖动同一条底层路径）
  Future<void> seekTo(Duration position) async {
    if (position <= Duration.zero) return;
    await _player.seek(position);
    ref.read(positionProvider.notifier).set(position);
  }

  /// 按比例 seek
  Future<void> seekRatio(double ratio) async {
    final total = ref.read(durationProvider);
    if (total <= Duration.zero) return;
    await _player.seek(total * ratio.clamp(0, 1));
  }

  /// 追加到队尾（同步播放器队列与 UI 队列）
  ///
  /// 只对**可编辑队列**生效（最近播放）。歌单即队列：往歌单队列里追加一首歌
  /// 等于悄悄改歌单，必须由"添加到歌单"这类显式动作来做。
  bool addToQueue(Song song) {
    if (!ref.read(queueProvider).editable) return false;
    final next = [..._player.queue, song];
    _player.setQueue(next);
    ref.read(queueProvider.notifier).setSongs(next);
    return true;
  }

  /// 从队列移除下标（返回被移除的歌曲）
  Song? removeFromQueue(int index) {
    final queue = List.of(_player.queue);
    if (index < 0 || index >= queue.length) return null;
    if (!ref.read(queueProvider).editable) return null;
    final removed = queue.removeAt(index);
    _player.setQueue(queue);
    ref.read(queueProvider.notifier).setSongs(queue);
    return removed;
  }

  /// 用新顺序覆盖队列（拖动排序用）
  void reorderQueue(int from, int to) {
    final queue = List.of(_player.queue);
    if (from < 0 || from >= queue.length) return;
    if (!ref.read(queueProvider).editable) return;
    final moving = queue.removeAt(from);
    queue.insert(to.clamp(0, queue.length), moving);
    _player.setQueue(queue);
    ref.read(queueProvider.notifier).setSongs(queue);
  }

  /// 清空队列（默认保留当前播放的那首）
  void clearQueue({bool keepCurrent = true}) {
    final currentKey = ref.read(currentTrackIdProvider);
    final kept = keepCurrent
        ? _player.queue.where((s) => s.globalKey == currentKey).toList()
        : <Song>[];
    if (!ref.read(queueProvider).editable) return;
    _player.setQueue(kept);
    ref.read(queueProvider.notifier).setSongs(kept);
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
  // 先订阅再扫盘：广播是 broadcast 流，订阅晚了会丢掉"索引就绪"那一次通知
  final sub = cache.changes.listen((_) {
    ref.read(audioCacheVersionProvider.notifier).bump();
  });
  ref.onDispose(sub.cancel);
  unawaited(cache.init().then((_) {
    // 兜底：即使 init 的广播早于订阅（或实现没发），这里也刷新一次，
    // 保证启动时先渲染的列表能拿到正确的「离线可播」状态
    ref.read(audioCacheVersionProvider.notifier).bump();
  }));
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

/// 播放地址解析结果：要么可直接播，要么卡在源站人机验证上
///
/// 为什么不用空串表示"没地址"：源站要求人机验证是一种**可继续**的状态
/// （用户输入验证码后就能播），不是失败。两者混在一起，UI 只会说"无法播放"，
/// 用户也无从分辨是解析坏了还是源站拦了。
class PlayResolution {
  /// 可直接播放的地址（未卡验证时非空）
  final String url;

  /// 源站人机验证挑战（image / key / 回传字段名）
  final PlaybackChallenge? challenge;

  const PlayResolution({this.url = '', this.challenge});

  /// 是否拿到可直接播放的地址
  bool get hasUrl => url.isNotEmpty;

  /// 是否卡在源站人机验证
  bool get needsChallenge => challenge != null;
}

/// 一次待处理的人机验证（等用户输入验证码）
class PendingCaptcha {
  /// 触发验证的那首歌（验证通过后继续播它）
  final Song song;

  /// 源站给的挑战（含验证图与 key）
  final PlaybackChallenge challenge;

  const PendingCaptcha(this.song, this.challenge);
}

/// 待处理的人机验证（null = 没有；UI 监听它来弹验证面板）
class PendingCaptchaNotifier extends Notifier<PendingCaptcha?> {
  @override
  PendingCaptcha? build() => null;

  /// 设置（null 表示用户已取消，或已提交成功）
  void set(PendingCaptcha? value) => state = value;
}

/// 提交验证码的结果
///
/// [challenge] 非空表示"没通过但源站给了新图"，面板据此就地刷新。
class CaptchaSubmitResult {
  /// 是否通过（通过即已开始播放）
  final bool ok;

  /// 未通过时源站给的新挑战（保持原图时为 null）
  final PlaybackChallenge? challenge;

  const CaptchaSubmitResult({required this.ok, this.challenge});
}

/// 待处理的人机验证 Provider
final pendingCaptchaProvider =
    NotifierProvider<PendingCaptchaNotifier, PendingCaptcha?>(
        PendingCaptchaNotifier.new);

/// 解析「实际要播的地址」：已下载 → 播放缓存 → 源
///
/// 前两者命中时**完全不请求源**（源失效/断网也能播）。回源那一趟顺带把元数据
/// 登记给 enrich 复用，所以一次播放只请求一次详情。
///
/// [captchaCode]/[captchaKey]：源站要求人机验证时，带用户输入的验证码重试；
/// 验证码由用户提供，这里只负责按源站要求回传。
final playSourceResolverProvider = Provider<
    Future<PlayResolution> Function(Song song,
        {String? captchaCode, String? captchaKey})>((ref) {
  return (song, {String? captchaCode, String? captchaKey}) async {
    final cache = ref.read(audioCacheProvider);
    // ① 用户主动下载过的文件
    final downloaded = await cache.downloadedUrlFor(song);
    if (downloaded != null && downloaded.isNotEmpty) {
      return PlayResolution(url: downloaded);
    }
    // ② 播放缓存（离线可用）
    final cached = cache.localUrlFor(song.globalKey);
    if (cached != null) return PlayResolution(url: cached);
    // ③ 回源：顺带拿元数据，登记 + 落库
    final info = await ref.read(sourceManagerProvider).getPlayable(
          song.sourceId,
          song.id,
          captchaCode: captchaCode,
          captchaKey: captchaKey,
        );
    final meta = info.meta;
    if (meta != null) {
      final svc = ref.read(songMetadataServiceProvider);
      svc.rememberDetail(meta); // 供紧随其后的 enrich 复用，避免重复请求详情
      unawaited(svc.enrich(song, detail: meta));
    }
    // 源站要求人机验证：如实回传挑战（含验证图），交给 UI 让用户自己过验证
    if (info.url.isEmpty && info.needsChallenge) {
      return PlayResolution(challenge: info.challenge);
    }
    return PlayResolution(url: info.url);
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

/// 歌单拼贴封面（**唯一实现**，所有页面共用）
///
/// 为什么必须唯一：此前首页 / 音乐库 / 全部歌单 / 歌单详情 / 其他歌单各自实现了
/// 一遍，于是同一个歌单在不同页面出现不同封面：
///   * 卡片页只读快照封面、还过滤掉空值 → 缺封面就少格子，后面的格子还被挤动；
///   * 详情页走 [resolveSongCover]（快照 → 元数据缓存）→ 四张齐全；
///   * 其他歌单用 songSnapshots.values（map 顺序）→ 顺序也可能不同。
/// 这里统一：**按曲目顺序**取前 4 首，逐首走与行/卡片一致的回落链，缺封面**留空位**
/// （空位由拼贴画补位色）—— 同一歌单在任何页面的格子数、顺序、内容都一致。
///
/// [songs] 非空时优先用它（详情页手上有完整曲目，回落链更全）。
List<String> resolvePlaylistCovers(
  WidgetRef ref,
  Playlist playlist, {
  List<Song>? songs,
}) {
  final covers = <String>[];
  for (var i = 0; i < playlist.songKeys.length && covers.length < 4; i++) {
    final key = playlist.songKeys[i];
    final full = (songs != null && i < songs.length) ? songs[i] : null;
    final song = full ?? playlist.songSnapshots[key];
    covers.add(song == null ? '' : (resolveSongCover(ref, song) ?? ''));
  }
  return covers;
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

// ==================== 歌词（全部来自真实音乐源） ====================

/// 当前曲目歌词：只问音乐源，不在 App 内做演示文本兜底
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

/// 源启用状态的版本号 —— UI 侧**唯一的触发源**
///
/// 收敛前的毛病（用户要求收敛）：UI 另存了一份 Map<String,bool>（旧 sourceEnabledProvider），
/// 与 SourceManager 内部的 _enabledStatus 是**两份真相**。只要有一条路径绕过 UI 直接调
/// manager.setSourceEnabled（启动时注册内置源、订阅库加载新源都这么做），界面就会失真：
/// 源实际在参与搜索，列表里却显示「已停用」。
///
/// 现在真值只有 manager 一个，UI 只观察这个版本号；manager 状态一变就回调 bump。
class SourceEnabledVersionNotifier extends Notifier<int> {
  @override
  int build() {
    final manager = ref.watch(sourceManagerProvider);
    // 任何地方改 manager 的启用状态 → 通知 UI 重建（这就是「单一真相」的闭环）
    manager.onEnabledChanged = (_, __) => bump();
    ref.onDispose(() => manager.onEnabledChanged = null);
    // 首次被观察时把持久化的启用状态应用回 manager（懒执行，与旧行为一致）
    unawaited(SourceEnabledActions(ref).restore());
    return 0;
  }

  /// 标记启用状态已变
  void bump() => state = state + 1;
}

/// 源启用状态版本 Provider
final sourceEnabledVersionProvider =
    NotifierProvider<SourceEnabledVersionNotifier, int>(
        SourceEnabledVersionNotifier.new);

/// 源启用状态的操作入口：**唯一**会落库的地方
class SourceEnabledActions {
  /// 构造
  SourceEnabledActions(this._ref);

  final Ref _ref;

  /// 启动恢复：把 settings 里的 source_enabled_<id> 应用回 manager
  Future<void> restore() async {
    final manager = _ref.read(sourceManagerProvider);
    final all = await _ref.read(settingsDaoProvider).getAll();
    for (final entry in all.entries) {
      if (!entry.key.startsWith('source_enabled_')) continue;
      final id = entry.key.substring('source_enabled_'.length);
      final value = entry.value == '1';
      // 相等时 manager 内部会短路，不会误触发 onEnabledChanged
      manager.setSourceEnabled(id, value);
    }
  }

  /// 切换某个源的启用状态：改 manager（真值）+ 落库（持久化）
  Future<void> set(String sourceId, bool enabled) async {
    _ref.read(sourceManagerProvider).setSourceEnabled(sourceId, enabled);
    await _ref
        .read(settingsDaoProvider)
        .set('source_enabled_$sourceId', enabled ? '1' : '0');
  }
}

/// 源启用状态操作 Provider
final sourceEnabledActionsProvider =
    Provider<SourceEnabledActions>(SourceEnabledActions.new);

/// 每个源的启用状态（**派生视图**，不是第二份状态）
///
/// 保留 map 形状是为了让「设置页/我的页」这类需要整张表的界面读起来不变。
final enabledSourceMapProvider = Provider<Map<String, bool>>((ref) {
  ref.watch(sourceEnabledVersionProvider);
  final manager = ref.watch(sourceManagerProvider);
  return {
    for (final s in manager.getAllSources())
      s.sourceInfo.id: manager.isSourceEnabled(s.sourceInfo.id),
  };
}, name: 'enabledSourceMapProvider');

/// 已启用的源（**派生视图**，唯一来源是 SourceManager.getEnabledSources）
///
/// 注意这是**功能**口径：搜索、推荐、封面等都该用它，必须包含 visible:false 的内置能力
/// （我最喜欢 / 本地音乐 / 自建歌曲），否则那些东西就不工作了。
final enabledSourcesProvider = Provider<List<MusicSource>>((ref) {
  ref.watch(sourceEnabledVersionProvider);
  return ref.watch(sourceManagerProvider).getEnabledSources();
}, name: 'enabledSourcesProvider');

/// 用户**可管理**的源（visible == true）—— 只用于**展示计数**
///
/// 为什么要和 [enabledSourcesProvider] 分开：内置能力（本地音乐 / 自建歌曲 / 我最喜欢）
/// 声明 visible:false，它们既不出现在「音乐源」列表里、也不能被停用，但**必须参与搜索**。
/// 以前各处文案各取各的：有的用全部源（7）、有的用可见源（4）当分母，分子却一律取全量，
/// 于是出现「4 个源 · 已启用 6 个」这种分子分母口径不一致的数字。
final manageableSourcesProvider = Provider<List<MusicSource>>((ref) {
  ref.watch(sourceEnabledVersionProvider);
  return ref
      .watch(sourceManagerProvider)
      .getAllSources()
      .where((s) => s.sourceInfo.visible)
      .toList(growable: false);
}, name: 'manageableSourcesProvider');

/// 可管理且已启用的源（展示计数用）
final enabledManageableSourcesProvider = Provider<List<MusicSource>>((ref) {
  ref.watch(sourceEnabledVersionProvider);
  final manager = ref.watch(sourceManagerProvider);
  return manager
      .getAllSources()
      .where((s) =>
          s.sourceInfo.visible && manager.isSourceEnabled(s.sourceInfo.id))
      .toList(growable: false);
}, name: 'enabledManageableSourcesProvider');

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
