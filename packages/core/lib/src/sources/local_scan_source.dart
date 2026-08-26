/// 本地扫描源
///
/// 扫描指定目录下的音频文件，提取元数据，持久化到 SQLite（通过 SongDao），
/// 支持增量更新。
///
/// 元数据提取策略（优先级从高到低）：
/// 1. 若注入 AudioMetadataReader（如 audiotags），读取文件内嵌标签
///    （标题/歌手/专辑/时长），读取失败时退回文件名解析
/// 2. 文件名格式 "Artist - Title.mp3" → 解析出歌手和标题
/// 3. 文件名格式 "Title.mp3" → 标题=文件名，歌手=父目录名

import 'dart:io';
import 'package:core/core.dart';

/// 支持的音频扩展名
const Set<String> _audioExtensions = {
  '.mp3', '.flac', '.aac', '.wav', '.m4a', '.ogg', '.opus',
};

class LocalScanSource extends MusicSource {
  final SongDao _songDao;
  final SettingsDao? _settingsDao;
  final AudioMetadataReader? _metadataReader;

  /// 内存缓存（从数据库加载后缓存，搜索时用）
  List<Song> _cache = [];
  bool _initialized = false;

  LocalScanSource(this._songDao, [this._settingsDao, this._metadataReader]);

  @override
  final SourceInfo sourceInfo = const SourceInfo(
    id: 'local_scan',
    name: '本地音乐',
    type: SourceType.local,
    enabled: true,
  );

  @override
  Future<void> init() async {
    await loadFromDatabase();
    _initialized = true;
  }

  @override
  Future<void> dispose() async {
    _cache = [];
    _initialized = false;
  }

  /// 从数据库加载已扫描的歌曲
  Future<void> loadFromDatabase() async {
    final all = await _songDao.searchSongs('');
    _cache = all.where((s) => s.sourceId == 'local_scan').toList();
  }

  /// 扫描指定目录，返回新增/更新的歌曲数
  ///
  /// 递归扫描目录下所有音频文件，解析文件名提取元数据，
  /// 通过 SongDao 持久化。已存在的文件跳过（增量更新）。
  Future<int> scanDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      throw ArgumentError('目录不存在: $dirPath');
    }

    // 已扫描的文件路径集合（用于增量更新）
    final existingPaths = <String>{};
    for (final song in _cache) {
      if (song.localPath != null) {
        existingPaths.add(song.localPath!);
      }
    }

    var newCount = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.path;
      final ext = path.toLowerCase().substring(path.lastIndexOf('.'));
      if (!_audioExtensions.contains(ext)) continue;

      // 增量更新：跳过已扫描的文件
      if (existingPaths.contains(path)) continue;

      // 解析元数据：优先读文件内嵌标签，失败退回文件名解析
      final fileName = path.substring(path.lastIndexOf(Platform.pathSeparator) + 1);
      final nameWithoutExt = fileName.substring(0, fileName.lastIndexOf('.'));
      final parsed = _parseFileName(nameWithoutExt, dirPath, path);

      var title = parsed.title;
      var artist = parsed.artist;
      String? album;
      int? durationMs;

      if (_metadataReader != null) {
        try {
          final meta = await _metadataReader.read(path);
          if (meta != null) {
            if (meta.title != null && meta.title!.isNotEmpty) {
              title = meta.title!;
            }
            if (meta.artist != null && meta.artist!.isNotEmpty) {
              artist = meta.artist!;
            }
            album = meta.album;
            durationMs = meta.durationMs;
          }
        } catch (_) {
          // 元数据读取失败时退回文件名解析结果
        }
      }

      // 创建 Song
      final song = Song(
        id: 'ls_${path.hashCode.toUnsigned(32).toString()}',
        sourceId: 'local_scan',
        title: title,
        artist: artist,
        album: album,
        duration: durationMs,
        localPath: path,
        extra: {'extension': ext, 'file_name': fileName},
      );

      // 持久化到数据库
      await _songDao.insertSong(song);
      _cache.add(song);
      newCount++;
    }

    return newCount;
  }

  /// 从配置的扫描目录扫描（读取 settings 表的 scan_dir）
  Future<int> scanFromConfig() async {
    if (_settingsDao == null) {
      throw StateError('SettingsDao 未注入，无法读取扫描目录配置');
    }
    final dirPath = await _settingsDao.get('scan_dir');
    if (dirPath == null || dirPath.isEmpty) {
      throw StateError('未配置扫描目录，请在设置中添加');
    }
    return scanDirectory(dirPath);
  }

  /// 解析文件名提取标题和歌手
  ///
  /// 支持格式：
  /// - "Artist - Title" → artist=Artist, title=Title
  /// - "Title" → title=Title, artist=父目录名
  _ParsedMetadata _parseFileName(String name, String baseDir, String filePath) {
    // 尝试 "Artist - Title" 格式
    final dashIndex = name.indexOf(' - ');
    if (dashIndex > 0) {
      return _ParsedMetadata(
        artist: name.substring(0, dashIndex).trim(),
        title: name.substring(dashIndex + 3).trim(),
      );
    }

    // 退化：用父目录名作为歌手
    final parentDirPath = filePath.substring(
      0, filePath.lastIndexOf(Platform.pathSeparator),
    );
    final parentDirName = parentDirPath.substring(
      parentDirPath.lastIndexOf(Platform.pathSeparator) + 1,
    );
    return _ParsedMetadata(
      artist: parentDirName,
      title: name.trim(),
    );
  }

  /// 获取已扫描的歌曲列表
  List<Song> getScannedSongs() => List.unmodifiable(_cache);

  /// 清除所有扫描结果（内存 + 数据库）
  Future<void> clear() async {
    for (final song in _cache) {
      await _songDao.deleteSong(song.id, 'local_scan');
    }
    _cache = [];
  }

  @override
  Future<SearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 20,
  }) async {
    if (!_initialized) {
      return SearchResult(songs: [], sourceId: 'local_scan');
    }

    if (keyword.isEmpty) {
      return SearchResult(songs: _cache, sourceId: 'local_scan', hasMore: false);
    }

    final lower = keyword.toLowerCase();
    final matched = _cache
        .where((s) =>
            s.title.toLowerCase().contains(lower) ||
            s.artist.toLowerCase().contains(lower))
        .toList();

    // 本地源不分页，全量返回
    return SearchResult(songs: matched, sourceId: 'local_scan', hasMore: false);
  }

  @override
  Future<Song> getSongDetail(String id) async {
    final song = _cache.where((s) => s.id == id).firstOrNull;
    if (song == null) throw Exception('Song not found: $id');
    return song;
  }

  @override
  Future<String> getSongUrl(String id) async {
    final song = _cache.where((s) => s.id == id).firstOrNull;
    if (song == null) throw Exception('Song not found: $id');
    return song.localPath ?? song.playUrl ?? '';
  }

  @override
  Future<Lyrics?> getLyrics(String id) async {
    // 查找同名 .lrc 文件解析（如 /music/晴天.mp3 → /music/晴天.lrc）
    final song = _cache.where((s) => s.id == id).firstOrNull;
    if (song == null || song.localPath == null) return null;

    final lrcPath = _replaceExtension(song.localPath!, '.lrc');
    try {
      final file = File(lrcPath);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final lines = LrcParser.parse(content);
      if (lines.isEmpty) return null;
      return Lyrics(songId: song.id, sourceId: song.sourceId, lines: lines);
    } catch (_) {
      return null;
    }
  }

  /// 替换文件扩展名
  static String _replaceExtension(String path, String newExt) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '$path$newExt';
    return '${path.substring(0, dot)}$newExt';
  }

  @override
  Future<Album?> getAlbum(String id) async => null;

  @override
  Future<Artist?> getArtist(String id) async => null;

  @override
  Future<Playlist?> getPlaylist(String id) async => null;
}

/// 文件名解析结果
class _ParsedMetadata {
  final String title;
  final String artist;

  const _ParsedMetadata({required this.title, required this.artist});
}
