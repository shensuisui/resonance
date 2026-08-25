/// DownloadManager 的 SQLite + dio 实现
///
/// 使用 dio 下载文件到应用缓存目录，
/// 使用 SongDao 更新 localPath，
/// 维护下载队列和状态流。

import 'dart:async';
import 'dart:io';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DownloadManagerImpl implements DownloadManager {
  final Dio _dio;
  final SongDao _songDao;

  /// 下载任务表（按 songKey 索引）
  final _tasks = <String, DownloadTask>{};

  /// 取消令牌表
  final _cancelTokens = <String, CancelToken>{};

  /// 任务状态流控制器
  final _taskController = StreamController<List<DownloadTask>>.broadcast();

  DownloadManagerImpl({Dio? dio, required SongDao songDao})
      : _dio = dio ?? Dio(),
        _songDao = songDao;

  @override
  Stream<List<DownloadTask>> get taskStream => _taskController.stream;

  @override
  List<DownloadTask> getTasks() => _tasks.values.toList();

  @override
  Future<String?> download(Song song, {String? url}) async {
    final key = song.globalKey;

    // 已缓存则直接返回
    if (song.localPath != null && await File(song.localPath!).exists()) {
      _tasks[key] = DownloadTask(
        songKey: key,
        url: url,
        status: DownloadStatus.completed,
        progress: 1.0,
        localPath: song.localPath,
      );
      _notify();
      return song.localPath;
    }

    // 创建下载任务
    final downloadUrl = url ?? song.playUrl;
    if (downloadUrl == null || downloadUrl.isEmpty) {
      _tasks[key] = DownloadTask(
        songKey: key,
        url: null,
        status: DownloadStatus.failed,
        error: '无可用下载地址',
      );
      _notify();
      return null;
    }

    _tasks[key] = DownloadTask(
      songKey: key,
      url: downloadUrl,
      status: DownloadStatus.pending,
    );
    _notify();

    // 异步执行下载
    _executeDownload(song, downloadUrl);

    return null;
  }

  /// 实际执行下载
  Future<void> _executeDownload(Song song, String url) async {
    final key = song.globalKey;
    final cancelToken = CancelToken();
    _cancelTokens[key] = cancelToken;

    try {
      // 获取缓存目录
      final cacheDir = await getTemporaryDirectory();
      final fileName = '${key.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.mp3';
      final savePath = p.join(cacheDir.path, fileName);

      // 更新状态为下载中
      _tasks[key] = _tasks[key]!.copyWith(status: DownloadStatus.downloading);
      _notify();

      // 下载文件
      await _dio.download(
        url,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            _tasks[key] = _tasks[key]!.copyWith(progress: progress);
            _notify();
          }
        },
      );

      // 下载完成，更新 Song.localPath
      _tasks[key] = _tasks[key]!.copyWith(
        status: DownloadStatus.completed,
        progress: 1.0,
        localPath: savePath,
      );

      // 持久化 localPath
      await _songDao.updateSong(song.copyWith(localPath: savePath));

      _notify();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        _tasks[key] = _tasks[key]!.copyWith(status: DownloadStatus.cancelled);
      } else {
        _tasks[key] = _tasks[key]!.copyWith(
          status: DownloadStatus.failed,
          error: e.message,
        );
      }
      _notify();
    } catch (e) {
      _tasks[key] = _tasks[key]!.copyWith(
        status: DownloadStatus.failed,
        error: e.toString(),
      );
      _notify();
    } finally {
      _cancelTokens.remove(key);
    }
  }

  @override
  Future<void> cancel(String songKey) async {
    final cancelToken = _cancelTokens[songKey];
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel();
    }
    final existing = _tasks[songKey];
    if (existing != null) {
      _tasks[songKey] = existing.copyWith(status: DownloadStatus.cancelled);
    }
    _notify();
  }

  @override
  Future<void> deleteCache(String songKey) async {
    // 删除本地文件
    try {
      final path = await getLocalPath(songKey);
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    } catch (_) {}

    // 清除任务
    _tasks.remove(songKey);
    _notify();
  }

  @override
  Future<bool> isCached(String songKey) async {
    final path = await getLocalPath(songKey);
    if (path == null) return false;
    return File(path).exists();
  }

  @override
  Future<String?> getLocalPath(String songKey) async {
    // 从任务表查
    final task = _tasks[songKey];
    if (task?.localPath != null) return task!.localPath;
    final parts = songKey.split(':');
    if (parts.length != 2) return null;
    final song = await _songDao.getSong(parts[1], parts[0]);
    return song?.localPath;
  }

  /// 通知状态变化
  void _notify() {
    _taskController.add(_tasks.values.toList());
  }

  /// 释放资源
  void dispose() {
    _taskController.close();
  }
}
