/// 整包备份的导出/导入服务（纯 Dart 逻辑，不碰文件系统）
///
/// 分工：
///   * 本文件只管「数据库 <-> [BackupDocument]」的搬运与合并规则；
///   * 文件选择、写盘、系统分享由壳工程注入的 picker 完成（uiv2 不依赖平台包）；
///   * JSON 结构由 [BackupCodec] 负责，版本校验也在那里。
///
/// 合并语义（[BackupImportMode.merge]）：
///   * 歌单：同名歌单按 songKey 去重后追加（同名视为同一张，id 由名字推导，重复导入不产生副本）；
///   * 收藏 / 最近播放：已存在就跳过（不扰动现有顺序与时间）；
///   * 设置：只写白名单键，且已存在的键不覆盖（尊重本机当前选择）；
///   * 播放进度：已有同名队列就不覆盖。
/// 覆盖语义（[BackupImportMode.overwrite]）：先清空对应分区再写入。
library;

import 'package:core/core.dart';

/// 可导入/导出的数据分区（UI 上可以勾选其中一部分恢复）
enum BackupSection {
  /// 歌单（含曲目快照）
  playlists,

  /// 收藏
  favorites,

  /// 最近播放
  recent,

  /// 设置（白名单键）
  settings,

  /// 播放进度
  progress,
}

/// 导入模式
enum BackupImportMode {
  /// 合并：已存在的跳过、新歌单新建（重复导入不产生重复数据）
  merge,

  /// 覆盖：先清空对应分区再写入
  overwrite,
}

/// 单个分区的导入结果
class ImportSectionReport {
  /// 新增条数
  final int added;

  /// 跳过条数（已存在/不合法）
  final int skipped;

  /// 更新条数（同名歌单追加曲目、设置覆盖等）
  final int updated;

  /// 构造
  const ImportSectionReport({
    this.added = 0,
    this.skipped = 0,
    this.updated = 0,
  });

  /// 覆盖式累加（内部统计用）
  ImportSectionReport plus({int added = 0, int skipped = 0, int updated = 0}) =>
      ImportSectionReport(
        added: this.added + added,
        skipped: this.skipped + skipped,
        updated: this.updated + updated,
      );

  @override
  String toString() =>
      'added=$added, skipped=$skipped, updated=$updated';
}

/// 整份导入结果
class ImportReport {
  /// 每个分区的结果
  final Map<BackupSection, ImportSectionReport> sections;

  /// 非致命提示（例如「3 个非白名单设置键已忽略」）
  final List<String> warnings;

  /// 构造
  const ImportReport({required this.sections, this.warnings = const <String>[]});

  /// 某个分区结果（缺省视为 0）
  ImportSectionReport of(BackupSection section) =>
      sections[section] ?? const ImportSectionReport();

  /// 新增总数
  int get totalAdded =>
      sections.values.fold<int>(0, (sum, item) => sum + item.added);

  /// 跳过总数
  int get totalSkipped =>
      sections.values.fold<int>(0, (sum, item) => sum + item.skipped);

  /// 更新总数
  int get totalUpdated =>
      sections.values.fold<int>(0, (sum, item) => sum + item.updated);
}

/// 备份导入导出服务
class BackupService {
  /// 构造：注入需要的 DAO（[songDao] 可选，用于把本地曲目写进 songs 表）
  BackupService({
    required this.playlistDao,
    required this.favoritesDao,
    required this.recentPlaysDao,
    required this.settingsDao,
    required this.playProgressDao,
    this.songDao,
  });

  /// 歌单 DAO
  final PlaylistDao playlistDao;

  /// 收藏 DAO
  final FavoritesDao favoritesDao;

  /// 最近播放 DAO
  final RecentPlaysDao recentPlaysDao;

  /// 设置 DAO
  final SettingsDao settingsDao;

  /// 播放进度 DAO
  final PlayProgressDao playProgressDao;

  /// 歌曲 DAO（可选：导入本地曲目时写入，保证能搜到/播到）
  final SongDao? songDao;

  /// 允许导出/导入的设置键白名单
  ///
  /// 刻意不含 subscriptions（订阅地址属于用户私有 URL）与任何 cookie/token：
  /// 备份文件可能被分享出去，不能顺手把隐私带走。
  static const Set<String> exportableSettingKeys = <String>{
    'theme_mode',
    'play_mode',
    'volume',
    'wifi_only',
    'play_device',
    'scan_dir',
    'search_history',
    'audio_cache_play',
    'lyrics_open',
    'corner_radius',
    'seed_color',
    'last_queue',
  };

  /// 允许的前缀键（每个源一个开关：source_enabled_ + 源 id）
  static const List<String> exportableSettingPrefixes = <String>[
    'source_enabled_',
  ];

  /// 该设置键是否允许进出备份
  static bool isExportableSetting(String key) =>
      exportableSettingKeys.contains(key) ||
      exportableSettingPrefixes.any(key.startsWith);

  /// 导出整包
  ///
  /// [now] 只用于测试固定时间；默认取当前时间。
  Future<BackupDocument> exportAll({DateTime? now}) async {
    final playlists = await playlistDao.getAllPlaylists();
    final favorites = await favoritesDao.getAllFavoriteRecords();
    final recent = await recentPlaysDao.getRecentPlayRecords();
    final settings = await settingsDao.getAll();
    final progress = await playProgressDao.getAll();

    return BackupDocument(
      exportedAt: now ?? DateTime.now(),
      playlists: <BackupPlaylist>[
        for (final playlist in playlists)
          BackupPlaylist(
            name: playlist.name,
            songs: <BackupSong>[
              for (final key in playlist.songKeys)
                _backupSongFromSnapshot(key, playlist.songSnapshots[key]),
            ],
          ),
      ],
      favorites: <BackupFavorite>[
        for (final item in favorites)
          BackupFavorite(
            songKey: item.songKey,
            time: item.time,
            title: item.title,
            artist: item.artist,
            coverUrl: item.coverUrl,
          ),
      ],
      recent: <BackupRecent>[
        for (final item in recent)
          BackupRecent(
            songKey: item.songKey,
            playedAt: item.playedAt,
            title: item.title,
            artist: item.artist,
            coverUrl: item.coverUrl,
          ),
      ],
      settings: <String, String>{
        for (final entry in settings.entries)
          if (isExportableSetting(entry.key)) entry.key: entry.value,
      },
      progress: <BackupProgress>[
        for (final item in progress)
          BackupProgress(
            queueKind: item.queueKind,
            queueId: item.queueId,
            songKey: item.songKey,
            positionMs: item.positionMs,
            updatedAt: item.updatedAt,
          ),
      ],
    );
  }

  /// 导入一份备份
  ///
  /// [sections] 为 null 表示「全部分区」。
  Future<ImportReport> importDocument(
    BackupDocument document, {
    BackupImportMode mode = BackupImportMode.merge,
    Set<BackupSection>? sections,
  }) async {
    final selected = sections ?? BackupSection.values.toSet();
    final reports = <BackupSection, ImportSectionReport>{};
    final warnings = <String>[];
    final now = DateTime.now();

    if (selected.contains(BackupSection.playlists)) {
      reports[BackupSection.playlists] =
          await _importPlaylists(document.playlists, mode, now);
    }
    if (selected.contains(BackupSection.favorites)) {
      reports[BackupSection.favorites] =
          await _importFavorites(document.favorites, mode);
    }
    if (selected.contains(BackupSection.recent)) {
      reports[BackupSection.recent] =
          await _importRecent(document.recent, mode);
    }
    if (selected.contains(BackupSection.settings)) {
      reports[BackupSection.settings] =
          await _importSettings(document.settings, mode, warnings);
    }
    if (selected.contains(BackupSection.progress)) {
      reports[BackupSection.progress] =
          await _importProgress(document.progress, mode);
    }

    return ImportReport(sections: reports, warnings: warnings);
  }

  /// 歌单导入：同名合并（id 由名字推导，避免重复导入产生副本）
  Future<ImportSectionReport> _importPlaylists(
    List<BackupPlaylist> incoming,
    BackupImportMode mode,
    DateTime now,
  ) async {
    var report = const ImportSectionReport();
    final existing = await playlistDao.getAllPlaylists();
    final byName = <String, Playlist>{
      for (final playlist in existing) playlist.name: playlist,
    };

    if (mode == BackupImportMode.overwrite) {
      for (final playlist in existing) {
        await playlistDao.deletePlaylist(playlist.id);
      }
      byName.clear();
    }

    for (final backup in incoming) {
      final keys = <String>[];
      final snapshots = <String, Song>{};
      for (final song in backup.songs) {
        if (!song.songKey.contains(':')) continue;
        if (keys.contains(song.songKey)) continue; // 同一歌单内去重
        keys.add(song.songKey);
        final snapshot = _songFromBackupSong(song);
        if (snapshot != null) snapshots[song.songKey] = snapshot;
        await _persistLocalSong(song);
      }
      if (keys.isEmpty) {
        report = report.plus(skipped: 1);
        continue;
      }

      final local = byName[backup.name];
      if (local == null) {
        final created = Playlist(
          id: _playlistIdForName(backup.name),
          name: backup.name,
          songKeys: keys,
          songSnapshots: snapshots,
          createdTime: now,
          modifiedTime: now,
        );
        await playlistDao.insertPlaylist(created);
        byName[backup.name] = created;
        report = report.plus(added: 1);
        continue;
      }

      final mergedKeys = List<String>.from(local.songKeys);
      final mergedSnapshots = Map<String, Song>.from(local.songSnapshots);
      var appended = 0;
      for (final key in keys) {
        if (mergedKeys.contains(key)) continue;
        mergedKeys.add(key);
        final snapshot = snapshots[key];
        if (snapshot != null) mergedSnapshots[key] = snapshot;
        appended++;
      }
      if (appended == 0) {
        report = report.plus(skipped: 1);
        continue;
      }
      final updated = local.copyWith(
        songKeys: mergedKeys,
        songSnapshots: mergedSnapshots,
        modifiedTime: now,
      );
      await playlistDao.updatePlaylist(updated);
      byName[backup.name] = updated;
      report = report.plus(updated: 1);
    }
    return report;
  }

  /// 收藏导入：已存在的跳过（merge）/ 先清空（overwrite）
  Future<ImportSectionReport> _importFavorites(
    List<BackupFavorite> incoming,
    BackupImportMode mode,
  ) async {
    var report = const ImportSectionReport();
    final existing = <String>{
      for (final item in await favoritesDao.getAllFavoriteRecords())
        item.songKey,
    };

    if (mode == BackupImportMode.overwrite) {
      for (final key in existing) {
        await favoritesDao.removeFavorite(key);
      }
      existing.clear();
    }

    for (final item in incoming) {
      if (!item.songKey.contains(':')) {
        report = report.plus(skipped: 1);
        continue;
      }
      if (existing.contains(item.songKey)) {
        report = report.plus(skipped: 1);
        continue;
      }
      await favoritesDao.addFavorite(
        item.songKey,
        item.time > 0 ? item.time : DateTime.now().millisecondsSinceEpoch,
        title: item.title,
        artist: item.artist,
        coverUrl: item.coverUrl,
      );
      existing.add(item.songKey);
      report = report.plus(added: 1);
    }
    return report;
  }

  /// 最近播放导入：已存在的跳过（merge）/ 先清空（overwrite）
  Future<ImportSectionReport> _importRecent(
    List<BackupRecent> incoming,
    BackupImportMode mode,
  ) async {
    var report = const ImportSectionReport();
    final existing = <String>{
      for (final key in await recentPlaysDao.getRecentPlayKeys()) key,
    };

    if (mode == BackupImportMode.overwrite) {
      for (final key in existing) {
        await recentPlaysDao.deleteRecentPlay(key);
      }
      existing.clear();
    }

    for (final item in incoming) {
      if (!item.songKey.contains(':') || existing.contains(item.songKey)) {
        report = report.plus(skipped: 1);
        continue;
      }
      await recentPlaysDao.insertOrUpdateRecentPlay(
        item.songKey,
        item.playedAt > 0
            ? item.playedAt
            : DateTime.now().millisecondsSinceEpoch,
        title: item.title,
        artist: item.artist,
        coverUrl: item.coverUrl,
      );
      existing.add(item.songKey);
      report = report.plus(added: 1);
    }
    return report;
  }

  /// 设置导入：只认白名单；merge 不覆盖已有键，overwrite 先删白名单键
  Future<ImportSectionReport> _importSettings(
    Map<String, String> incoming,
    BackupImportMode mode,
    List<String> warnings,
  ) async {
    var report = const ImportSectionReport();
    final accepted = <String, String>{};
    var rejected = 0;
    for (final entry in incoming.entries) {
      if (isExportableSetting(entry.key)) {
        accepted[entry.key] = entry.value;
      } else {
        rejected++;
      }
    }
    if (rejected > 0) {
      warnings.add('已忽略 $rejected 个不在白名单内的设置键');
    }

    final local = await settingsDao.getAll();
    if (mode == BackupImportMode.overwrite) {
      for (final key in accepted.keys) {
        if (local.containsKey(key)) await settingsDao.delete(key);
      }
    }

    for (final entry in accepted.entries) {
      if (mode == BackupImportMode.merge && local.containsKey(entry.key)) {
        report = report.plus(skipped: 1);
        continue;
      }
      await settingsDao.set(entry.key, entry.value);
      report = report.plus(added: 1);
    }
    return report;
  }

  /// 播放进度导入：按「队列身份」去重
  Future<ImportSectionReport> _importProgress(
    List<BackupProgress> incoming,
    BackupImportMode mode,
  ) async {
    var report = const ImportSectionReport();
    final current = await playProgressDao.getAll();
    final existing = <String>{for (final item in current) item.identity};

    if (mode == BackupImportMode.overwrite) {
      for (final item in current) {
        await playProgressDao.delete(item.queueKind, item.queueId);
      }
      existing.clear();
    }

    for (final item in incoming) {
      if (!item.songKey.contains(':')) {
        report = report.plus(skipped: 1);
        continue;
      }
      final progress = PlayProgress(
        queueKind: item.queueKind,
        queueId: item.queueId,
        songKey: item.songKey,
        positionMs: item.positionMs,
        updatedAt: item.updatedAt,
      );
      if (existing.contains(progress.identity)) {
        report = report.plus(skipped: 1);
        continue;
      }
      await playProgressDao.upsert(progress);
      existing.add(progress.identity);
      report = report.plus(added: 1);
    }
    return report;
  }

  /// 歌单里本地曲目（local_scan / local_custom）写回 songs 表
  ///
  /// 为什么：歌单快照只用于显示，真正播放/搜索要查 songs 表（LocalScanSource
  /// 与 LocalCustomSource 都读它）。不写回的话，导入的本地歌单「看得见播不了」。
  Future<void> _persistLocalSong(BackupSong backup) async {
    final dao = songDao;
    if (dao == null) return;
    final parts = backup.songKey.split(':');
    if (parts.length != 2) return;
    final localPath = backup.localPath;
    if (parts[0] != 'local_scan' && parts[0] != 'local_custom') return;
    if (localPath == null || localPath.isEmpty) return;
    await dao.insertSong(Song(
      id: parts[1],
      sourceId: parts[0],
      title: backup.title,
      artist: backup.artist,
      duration: backup.duration,
      coverUrl: backup.coverUrl,
      localPath: localPath,
    ));
  }

  /// 快照缺失时用 songKey 兜底（标题留空由 UI 显示占位）
  BackupSong _backupSongFromSnapshot(String songKey, Song? snapshot) {
    if (snapshot != null) {
      return BackupSong(
        songKey: songKey,
        title: snapshot.title,
        artist: snapshot.artist,
        duration: snapshot.duration,
        coverUrl: snapshot.coverUrl,
        localPath: snapshot.localPath,
      );
    }
    final parts = songKey.split(':');
    return BackupSong(
      songKey: songKey,
      title: parts.length == 2 ? parts[1] : songKey,
      artist: '',
    );
  }

  /// 备份曲目 -> Song 快照（用于歌单 songSnapshots）
  Song? _songFromBackupSong(BackupSong backup) {
    final parts = backup.songKey.split(':');
    if (parts.length != 2) return null;
    return Song(
      id: parts[1],
      sourceId: parts[0],
      title: backup.title,
      artist: backup.artist,
      duration: backup.duration,
      coverUrl: backup.coverUrl,
      localPath: backup.localPath,
    );
  }

  /// 歌单 id 由名字派生：同名歌单重复导入只会合并，不会产生副本
  String _playlistIdForName(String name) {
    var hash = 0;
    for (final code in name.codeUnits) {
      hash = (hash * 31 + code) & 0x7FFFFFFF;
    }
    return 'import_${hash.toRadixString(16)}';
  }
}
