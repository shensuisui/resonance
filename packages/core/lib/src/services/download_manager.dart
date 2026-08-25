/// 下载管理器抽象接口
///
/// 负责将在线歌曲下载到本地缓存目录，
/// 管理 download queue、取消、删除等操作。
/// 具体实现（dio + path_provider）在 db 包中。

import 'package:core/core.dart';

/// 下载状态
enum DownloadStatus {
  /// 等待中
  pending,
  /// 下载中
  downloading,
  /// 已完成
  completed,
  /// 已取消
  cancelled,
  /// 失败
  failed,
}

/// 下载任务信息
class DownloadTask {
  /// 歌曲 ID（全局键 sourceId:id）
  final String songKey;
  /// 播放地址（可能需要从源重新获取）
  final String? url;
  /// 下载状态
  final DownloadStatus status;
  /// 下载进度（0.0 ~ 1.0）
  final double progress;
  /// 本地文件路径（下载完成后设置）
  final String? localPath;
  /// 错误信息（失败时）
  final String? error;

  const DownloadTask({
    required this.songKey,
    required this.url,
    required this.status,
    this.progress = 0.0,
    this.localPath,
    this.error,
  });

  DownloadTask copyWith({
    DownloadStatus? status,
    double? progress,
    String? localPath,
    String? error,
    String? url,
  }) {
    return DownloadTask(
      songKey: songKey,
      url: url ?? this.url,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      localPath: localPath ?? this.localPath,
      error: error ?? this.error,
    );
  }
}

/// 下载管理器抽象接口
///
/// 由 db 包提供具体实现（DownloadManagerImpl）。
/// 上层（ui / Riverpod provider）通过此接口操作下载。
abstract class DownloadManager {
  /// 下载歌曲到本地缓存
  ///
  /// 如果歌曲已有缓存（localPath 不为空）直接返回。
  /// 否则使用 [url] 下载，完成后更新 Song.localPath。
  Future<String?> download(Song song, {String? url});

  /// 取消下载
  Future<void> cancel(String songKey);

  /// 删除本地缓存
  Future<void> deleteCache(String songKey);

  /// 检查是否已缓存
  Future<bool> isCached(String songKey);

  /// 获取本地缓存路径
  ///
  /// 返回 null 表示未缓存。
  Future<String?> getLocalPath(String songKey);

  /// 获取当前下载任务列表
  List<DownloadTask> getTasks();

  /// 下载状态流（用于 UI 监听）
  Stream<List<DownloadTask>> get taskStream;
}
