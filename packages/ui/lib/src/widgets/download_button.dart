/// 下载按钮 Widget
///
/// 显示歌曲的下载状态并支持操作：
/// - 未下载 → 下载图标，点击开始下载
/// - 下载中 → 圆形进度指示，点击取消
/// - 已缓存 → 对勾图标，点击删除缓存
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。
library;

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../providers/providers.dart';

class DownloadButton extends ConsumerWidget {
  final Song song;

  const DownloadButton({super.key, required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final manager = ref.watch(downloadManagerProvider);
    final tasks = ref.watch(downloadTasksProvider).value ?? const [];
    final task = tasks
        .where((t) => t.songKey == song.globalKey)
        .firstOrNull;

    // 有任务：按状态显示
    if (task != null) {
      switch (task.status) {
        case DownloadStatus.pending:
        case DownloadStatus.downloading:
          return _progressButton(context, cs, ref, manager, task);
        case DownloadStatus.completed:
          return _completedButton(context, cs, ref, manager);
        case DownloadStatus.cancelled:
        case DownloadStatus.failed:
          // 取消/失败 → 允许重新下载
          return _downloadButton(context, cs, ref, manager);
      }
    }

    // 无任务：检查是否已缓存（localPath 有值视为已下载）
    if (song.localPath != null && song.localPath!.isNotEmpty) {
      return _completedButton(context, cs, ref, manager);
    }
    return _downloadButton(context, cs, ref, manager);
  }

  Widget _downloadButton(
      BuildContext context, ColorScheme cs, WidgetRef ref, DownloadManager m) {
    return IconButton(
      icon: Icon(Icons.download_rounded, color: cs.onSurfaceVariant, size: 20),
      tooltip: '下载',
      onPressed: () => m.download(song),
    );
  }

  Widget _progressButton(BuildContext context, ColorScheme cs, WidgetRef ref,
      DownloadManager m, DownloadTask task) {
    final progress = (task.progress * 100).round();
    return IconButton(
      icon: SizedBox(
        width: 22,
        height: 22,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: task.progress > 0 ? task.progress : null,
              strokeWidth: 2.5,
              color: cs.primary,
            ),
            Center(
              child: Text(
                '$progress%',
                style: TextStyle(fontSize: 6, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
      tooltip: '下载中，点击取消',
      onPressed: () => m.cancel(song.globalKey),
    );
  }

  Widget _completedButton(
      BuildContext context, ColorScheme cs, WidgetRef ref, DownloadManager m) {
    return IconButton(
      icon: Icon(Icons.check_circle_rounded, color: cs.primary, size: 20),
      tooltip: '已缓存，点击删除',
      onPressed: () => m.deleteCache(song.globalKey),
    );
  }
}

/// Widget 预览：未下载状态（下载图标）
///
/// 预览环境无真实服务，用内存 DAO + 假下载管理器注入。
@Preview(name: 'DownloadButton 未下载', group: 'DownloadButton')
Widget downloadButtonPreview() {
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWith((ref) => InMemoryDatabaseProvider()),
  ]);
  final song = Song(
    id: '1', sourceId: 'netease', title: '晴天', artist: '周杰伦',
  );
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(body: Center(child: DownloadButton(song: song))),
    ),
  );
}

/// Widget 预览：已缓存状态（对勾图标）
@Preview(name: 'DownloadButton 已缓存', group: 'DownloadButton')
Widget downloadButtonCachedPreview() {
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWith((ref) => InMemoryDatabaseProvider()),
  ]);
  final song = Song(
    id: '2', sourceId: 'netease', title: '稻香', artist: '周杰伦',
    localPath: '/cached/2.mp3',
  );
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(body: Center(child: DownloadButton(song: song))),
    ),
  );
}
