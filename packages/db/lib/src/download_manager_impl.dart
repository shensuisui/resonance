/// DownloadManager 的 SQLite + dio 实现（P2：持久化 + support 目录 + 可读命名）
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:core/core.dart';
import 'package:audiotags/audiotags.dart';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tag_writer.dart';

class DownloadManagerImpl implements DownloadManager {
  final Dio _dio;
  final SongDao _songDao;
  final DownloadTaskDao? _taskDao;
  final AudioCacheFileAccess? _audioCache;
  final TagWriter _tagWriter;
  final SettingsDao? _settingsDao;

  /// 自定义下载根目录（测试用）；null → support/downloads
  final String? customCacheDir;

  /// 命名顺序：artist_title（默认）/ title_artist
  final String nameOrder;

  final _tasks = <String, DownloadTask>{};
  final _songs = <String, Song>{};
  final _cancelTokens = <String, CancelToken>{};
  final _partPaths = <String, String>{};
  final _pendingLyrics = <String, String?>{};
  final _progressMarks = <String, int>{};
  final _queue = <String>[];
  String? _active;
  final _taskController = StreamController<List<DownloadTask>>.broadcast();

  DownloadManagerImpl({
    Dio? dio,
    required SongDao songDao,
    DownloadTaskDao? downloadTaskDao,
    AudioCacheFileAccess? audioCache,
    TagWriter? tagWriter,
    SettingsDao? settingsDao,
    this.customCacheDir,
    this.nameOrder = 'artist_title',
  })  : _dio = dio ?? Dio(),
        _songDao = songDao,
        _taskDao = downloadTaskDao,
        _audioCache = audioCache,
        _tagWriter = tagWriter ?? AudioTagsTagWriter(),
        _settingsDao = settingsDao;

  @override
  Stream<List<DownloadTask>> get taskStream => _taskController.stream;

  @override
  List<DownloadTask> getTasks() => _tasks.values.toList();

  /// 启动时从数据库加载任务；中断的 downloading 标 failed（保留 .part 供重试）
  Future<void> init() async {
    final dao = _taskDao;
    if (dao == null) return;
    for (final loaded in await dao.getAll()) {
      var task = loaded;
      if (loaded.status == DownloadStatus.downloading) {
        task = loaded.copyWith(status: DownloadStatus.failed, error: '上次下载中断');
        await dao.upsert(task);
      }
      _tasks[task.songKey] = task;
    }
    _notify();
  }

  @override
  Future<String?> download(Song song, {
    String? url,
    Map<String, String>? headers,
    String? lyrics,
  }) async {
    final key = song.globalKey;

    final existing = _tasks[key];
    if (existing != null &&
        (existing.status == DownloadStatus.pending ||
            existing.status == DownloadStatus.downloading)) {
      return null; // 同曲在排队/下载中，忽略重复请求
    }

    if (song.localPath != null && await File(song.localPath!).exists()) {
      final done = DownloadTask(
        songKey: key,
        url: url,
        status: DownloadStatus.completed,
        progress: 1.0,
        localPath: song.localPath,
        createdAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
      );
      _tasks[key] = done;
      _notify();
      unawaited(_persist(done));
      return song.localPath;
    }

    // 缓存命中：magic 校验通过才拷贝，拷后删缓存（不联网）
    if (await _tryCopyFromCache(song)) {
      return _tasks[song.globalKey]?.localPath;
    }

    final downloadUrl = url ?? song.playUrl;
    if (downloadUrl == null || downloadUrl.isEmpty) {
      final failed = DownloadTask(
        songKey: key,
        url: null,
        status: DownloadStatus.failed,
        error: '无可用下载地址',
        createdAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
      );
      _tasks[key] = failed;
      _notify();
      unawaited(_persist(failed));
      return null;
    }

    _songs[key] = song;
    _pendingLyrics[key] = lyrics;
    final pending = DownloadTask(
      songKey: key,
      url: downloadUrl,
      status: DownloadStatus.pending,
      createdAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
    );
    _tasks[key] = pending;
    _queue.add(key);
    _notify();
    unawaited(_persist(pending));
    unawaited(_schedule(headers));
    return null;
  }

  Map<String, String> _headersFor(String key) => const {};

  Future<void> _schedule(Map<String, String>? headers) async {
    if (_active != null) return;
    while (_queue.isNotEmpty) {
      final key = _queue.removeAt(0);
      final task = _tasks[key];
      if (task == null) continue;
      if (task.status == DownloadStatus.cancelled ||
          task.status == DownloadStatus.completed) {
        continue;
      }
      _active = key;
      final song = _songs[key];
      final url = task.url;
      if (song == null || url == null) {
        _active = null;
        continue;
      }
      await _execute(song, url, headers ?? _headersFor(key));
      _active = null;
    }
  }

  /// 写入基础标签 + 封面缩略图 + 歌词；返回 warning（null 表示全部成功）。
  Future<String?> _writeMetadata(
    String path,
    Song song,
    String? lyrics,
    Map<String, String> headers,
  ) async {
    final ext = p.extension(path).toLowerCase();
    if (!{'.mp3', '.m4a', '.flac', '.ogg', '.opus'}.contains(ext)) {
      return '未写入标签：不支持的格式 $ext';
    }
    final warnings = <String>[];
    final coverSize = await _effectiveCoverSize();
    final coverQuality = await _effectiveCoverQuality();
    var pictures = <Picture>[];
    final coverUrl = song.coverUrl;
    if (coverUrl != null && coverUrl.isNotEmpty) {
      try {
        final res = await _dio.get<List<int>>(
          coverUrl,
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 15),
            headers: headers,
          ),
        );
        final raw = res.data;
        if (raw == null || raw.isEmpty) throw StateError('封面为空');
        final decoded = img.decodeImage(Uint8List.fromList(raw));
        if (decoded == null) throw StateError('封面解码失败');
        final square = img.copyResizeCropSquare(decoded, size: coverSize);
        final jpg = img.encodeJpg(square, quality: coverQuality);
        pictures = [
          Picture(
            pictureType: PictureType.coverFront,
            mimeType: MimeType.jpeg,
            bytes: Uint8List.fromList(jpg),
          ),
        ];
      } catch (_) {
        warnings.add('封面写入失败');
      }
    }
    final hasLyrics = lyrics != null && lyrics.trim().isNotEmpty;
    if (!hasLyrics) warnings.add('无歌词');
    try {
      await _tagWriter.write(
        path,
        Tag(
          title: song.title,
          trackArtist: song.artist,
          album: song.album,
          lyrics: hasLyrics ? lyrics : null,
          pictures: pictures,
        ),
      );
    } catch (_) {
      warnings.add('标签写入失败');
    }
    return warnings.isEmpty ? null : warnings.join('；');
  }

  /// 缓存命中则拷贝为下载文件；成功返回 true（不联网）。
  Future<bool> _tryCopyFromCache(Song song) async {
    final cache = _audioCache;
    if (cache == null) return false;
    final key = song.globalKey;
    final srcPath = cache.filePathFor(key);
    if (srcPath == null) return false;
    final src = File(srcPath);
    if (!await src.exists()) return false;

    // magic 校验：识别不出音频格式就不拷贝，退回联网下载
    final ext = detectAudioExtension(await src.openRead(0, 16).first);
    if (ext == null) return false;

    final root = await _downloadRoot();
    final dir = Directory(p.join(root.path, _sourceIdOf(key)));
    if (!await dir.exists()) await dir.create(recursive: true);
    final existing = (await dir
            .list()
            .where((e) => e is File && !e.path.endsWith('.part'))
            .map((e) => p.basename(e.path))
            .toList())
        .toSet();
    final name = uniqueFileName(
      buildDownloadFileName(
        title: song.title,
        artist: song.artist,
        order: nameOrder,
        extension: ext,
      ),
      existing,
    );
    final dest = p.join(dir.path, name);
    try {
      await src.copy(dest);
    } catch (_) {
      return false;
    }
    try {
      await cache.remove(key);
    } catch (_) {}

    final done = DownloadTask(
      songKey: key,
      url: song.playUrl,
      status: DownloadStatus.completed,
      progress: 1.0,
      localPath: dest,
      createdAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
    );
    _tasks[key] = done;
    _notify();
    await _songDao.upsertSong(song.copyWith(localPath: dest));
    await _persist(done);
    return true;
  }

  Future<Directory> _downloadRoot() async {
    final base = customCacheDir ??
        p.join((await getApplicationSupportDirectory()).path, 'downloads');
    final dir = Directory(base);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _sourceIdOf(String songKey) {
    final parts = songKey.split(':');
    final sid = parts.isEmpty ? '' : parts.first;
    return sanitizeFileNamePart(sid).isEmpty ? 'unknown' : sanitizeFileNamePart(sid);
  }

  String _partNameOf(String songKey) =>
      '${base64Url.encode(utf8.encode(songKey)).replaceAll('=', '')}.part';

  String? _extFromUrl(String url) {
    final ext = p.extension(Uri.tryParse(url)?.path ?? '').toLowerCase();
    const ok = {'.mp3', '.m4a', '.mp4', '.flac', '.ogg', '.opus', '.aac', '.wav'};
    if (!ok.contains(ext)) return null;
    return ext.substring(1).replaceAll('mp4', 'm4a');
  }

  String? _extFromContentType(String? ct) {
    if (ct == null) return null;
    final t = ct.toLowerCase();
    if (t.contains('mpeg') || t.contains('mp3')) return 'mp3';
    if (t.contains('mp4') || t.contains('m4a') || t.contains('aac')) return 'm4a';
    if (t.contains('flac')) return 'flac';
    if (t.contains('ogg') || t.contains('opus')) return 'ogg';
    if (t.contains('wav')) return 'wav';
    return null;
  }

  Future<String?> _sniffExt(String path) async {
    try {
      final bytes = await File(path).openRead(0, 16).first;
      return detectAudioExtension(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<String> _effectiveNameOrder() async {
    final v = await _settingsDao?.get(DownloadSettingsKeys.nameOrder);
    return v == 'title_artist' ? 'title_artist' : nameOrder;
  }

  Future<int> _effectiveCoverSize() async {
    final raw = int.tryParse(await _settingsDao?.get(DownloadSettingsKeys.coverSize) ?? '');
    final v = raw ?? 256;
    return v.clamp(64, 1024);
  }

  Future<int> _effectiveCoverQuality() async {
    final raw = int.tryParse(await _settingsDao?.get(DownloadSettingsKeys.coverQuality) ?? '');
    final v = raw ?? 85;
    return v.clamp(50, 95);
  }

  Future<void> _execute(Song song, String url, Map<String, String> headers) async {
    final key = song.globalKey;
    final lyrics = _pendingLyrics.remove(key);
    final cancelToken = CancelToken();
    _cancelTokens[key] = cancelToken;
    final root = await _downloadRoot();
    final sourceDir = Directory(p.join(root.path, _sourceIdOf(key)));
    if (!await sourceDir.exists()) await sourceDir.create(recursive: true);
    final partPath = p.join(sourceDir.path, _partNameOf(key));
    _partPaths[key] = partPath;

    try {
      _tasks[key] = _tasks[key]!.copyWith(status: DownloadStatus.downloading);
      _notify();
      await _persist(_tasks[key]!);

      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final file = File(partPath);
          var existingSize = 0;
          if (await file.exists()) existingSize = await file.length();

          final response = await _dio.get<ResponseBody>(
            url,
            options: Options(
              responseType: ResponseType.stream,
              followRedirects: true,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: {
                ...headers,
                if (existingSize > 0) 'range': 'bytes=$existingSize-',
              },
            ),
            cancelToken: cancelToken,
          );

          final append = response.statusCode == HttpStatus.partialContent;
          final base = append ? existingSize : 0;
          final total = base + (response.data?.contentLength ?? 0);
          final raf = await file.open(mode: append ? FileMode.append : FileMode.write);
          var received = 0;
          try {
            await for (final chunk in response.data!.stream) {
              await raf.writeFrom(chunk);
              received += chunk.length;
              if (total > 0) {
                final progress = (base + received) / total;
                _tasks[key] =
                    _tasks[key]!.copyWith(progress: progress.clamp(0.0, 1.0));
                _notify();
                _persistProgress(_tasks[key]!);
              }
            }
          } finally {
            await raf.close();
          }

          // 扩展名：URL → Content-Type → 文件头 magic → mp3
          final ext = _extFromUrl(url) ??
              _extFromContentType(response.headers.value('content-type')) ??
              await _sniffExt(partPath) ??
              'mp3';
          final existingNames = (await sourceDir
                  .list()
                  .where((e) => e is File && !e.path.endsWith('.part'))
                  .map((e) => p.basename(e.path))
                  .toList())
              .toSet();
          final order = await _effectiveNameOrder();
          final baseName = buildDownloadFileName(
            title: song.title,
            artist: song.artist,
            order: order,
            extension: ext,
          );
          final finalName = uniqueFileName(baseName, existingNames);
          final finalPath = p.join(sourceDir.path, finalName);
          await File(partPath).rename(finalPath);
          _partPaths.remove(key);

          final warning = await _writeMetadata(finalPath, song, lyrics, headers);
          _tasks[key] = _tasks[key]!.copyWith(
            status: DownloadStatus.completed,
            progress: 1.0,
            localPath: finalPath,
            totalBytes: total > 0 ? total : null,
            receivedBytes: base + received,
            warning: warning,
          );
          await _songDao.upsertSong(song.copyWith(localPath: finalPath));
          _notify();
          await _persist(_tasks[key]!);
          return;
        } on DioException catch (e) {
          if (e.type == DioExceptionType.cancel) {
            _tasks[key] = _tasks[key]!.copyWith(status: DownloadStatus.cancelled);
            _notify();
            await _persist(_tasks[key]!);
            await _deletePart(partPath);
            return;
          }
          final transient = e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.connectionError;
          if (transient && attempt < 2) {
            await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
            continue;
          }
          _tasks[key] = _tasks[key]!.copyWith(
            status: DownloadStatus.failed,
            error: e.message,
          );
          _notify();
          await _persist(_tasks[key]!);
          return;
        } catch (e) {
          _tasks[key] = _tasks[key]!.copyWith(
            status: DownloadStatus.failed,
            error: e.toString(),
          );
          _notify();
          await _persist(_tasks[key]!);
          return;
        }
      }
    } finally {
      _cancelTokens.remove(key);
    }
  }

  Future<void> _deletePart(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  @override
  Future<void> cancel(String songKey) async {
    _queue.remove(songKey);
    final token = _cancelTokens[songKey];
    if (token != null && !token.isCancelled) token.cancel();
    final existing = _tasks[songKey];
    if (existing != null) {
      _tasks[songKey] = existing.copyWith(status: DownloadStatus.cancelled);
      await _persist(_tasks[songKey]!);
    }
    final part = _partPaths[songKey];
    if (part != null) {
      await _deletePart(part);
      _partPaths.remove(songKey);
    }
    _notify();
  }

  @override
  Future<void> removeRecord(String songKey) async {
    final task = _tasks[songKey];
    if (task == null) return;
    if (task.status != DownloadStatus.failed &&
        task.status != DownloadStatus.cancelled) {
      return;
    }
    _tasks.remove(songKey);
    _songs.remove(songKey);
    await _taskDao?.delete(songKey);
    _notify();
  }

  @override
  Future<void> deleteCache(String songKey) async {
    try {
      final path = await getLocalPath(songKey);
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    } catch (_) {}
    final parts = songKey.split(':');
    if (parts.length == 2) {
      await _songDao.clearLocalPath(parts[1], parts[0]);
    }
    _tasks.remove(songKey);
    _songs.remove(songKey);
    await _taskDao?.delete(songKey);
    _notify();
  }

  @override
  Future<bool> isCached(String songKey) async {
    final path = await getLocalPath(songKey);
    if (path == null) return false;
    if (await File(path).exists()) return true;
    // 外部删除自愈：文件没了 → 清 local_path、删任务行，避免「幽灵已下载」
    await _healMissing(songKey);
    return false;
  }

  Future<void> _healMissing(String songKey) async {
    final parts = songKey.split(':');
    if (parts.length == 2) {
      await _songDao.clearLocalPath(parts[1], parts[0]);
    }
    _tasks.remove(songKey);
    await _taskDao?.delete(songKey);
    _notify();
  }

  @override
  Future<String?> getLocalPath(String songKey) async {
    final task = _tasks[songKey];
    if (task?.localPath != null) return task!.localPath;
    final parts = songKey.split(':');
    if (parts.length != 2) return null;
    final song = await _songDao.getSong(parts[1], parts[0]);
    return song?.localPath;
  }

  Future<void> _persist(DownloadTask task) async {
    final dao = _taskDao;
    if (dao == null) return;
    try {
      await dao.upsert(task);
    } catch (_) {}
  }

  void _persistProgress(DownloadTask task) {
    if (_taskDao == null) return;
    final pct = (task.progress * 20).floor();
    if (_progressMarks[task.songKey] == pct) return;
    _progressMarks[task.songKey] = pct;
    unawaited(_persist(task));
  }

  void _notify() {
    _taskController.add(_tasks.values.toList());
  }

  void dispose() {
    _taskController.close();
  }
}
