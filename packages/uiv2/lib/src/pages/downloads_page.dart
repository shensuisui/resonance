/// 下载任务（原型 renderDownloads）
///
/// 真实数据来自 core 的 DownloadManager（taskStream → downloadTasksProvider）；
/// 进度、状态与操作按钮按 DownloadStatus 渲染。
///
/// 任务只记了 songKey（sourceId:id），歌名要现解析：先看演示曲库的 Song 映射，
/// 再回源补一次详情，都拿不到时退回 songKey —— 不伪造歌名。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/rows.dart';
import '../components/sheets.dart';
import '../components/surfaces.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../providers/providers.dart';
import '../router.dart';
import '../widgets/page_shell.dart';

/// 下载任务页
class DownloadsPage extends ConsumerWidget {
  /// 构造页面
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final tasks = ref.watch(downloadTasksProvider).value ?? const <DownloadTask>[];
    // 所有写操作（取消 / 重试 / 删除缓存 / 清理已结束）都走 DownloadActions
    final actions = ref.read(downloadActionsProvider);

    final running = tasks.where((x) => x.status == DownloadStatus.downloading).length;
    final done = tasks.where((x) => x.status == DownloadStatus.completed).length;
    final failed = tasks.where((x) => x.status == DownloadStatus.failed).length;
    final cancelled = tasks.where((x) => x.status == DownloadStatus.cancelled).length;
    final summary = [
      if (running > 0) '下载中 $running',
      if (done > 0) '已完成 $done',
      if (failed > 0) '失败 $failed',
      if (cancelled > 0) '已取消 $cancelled',
    ];
    final summaryText = summary.isEmpty ? '没有下载任务' : summary.join(' · ');

    return PageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHead(
            title: '下载任务',
            sub: '下载进度、取消、重试与删除缓存都在这里；缓存文件放在应用支持目录。',
          ),
          if (tasks.isEmpty)
            UiV2Panel(
              child: UiV2Empty(
                title: '还没有下载任务',
                text: '在专辑或单曲的更多操作里点「下载」，任务会显示在这里。',
                icon: UiV2Icons.download,
                actions: UiV2Button(
                  label: '去音乐库看看',
                  variant: UiV2ButtonVariant.primary,
                  onTap: () => ref.read(navProvider.notifier).go('library'),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: UiV2Spacing.s3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '共 ${tasks.length} 个任务 · $summaryText',
                      style: UiV2Text.hint.copyWith(color: t.textDim),
                    ),
                  ),
                  UiV2GhostMini(
                    label: '清理已结束',
                    onTap: () async {
                      final cleared = await actions.clearFinished();
                      if (context.mounted) {
                        showUiV2Toast(
                          context,
                          cleared == 0 ? '没有可清理的记录' : '已清理 $cleared 条记录',
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            UiV2Panel(
              child: Column(
                children: [
                  for (final task in tasks) _DownloadRow(task: task),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单条下载任务（.dl）
class _DownloadRow extends ConsumerWidget {
  /// 任务快照（父级从 downloadTasksProvider 取）
  final DownloadTask task;

  const _DownloadRow({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final actions = ref.read(downloadActionsProvider);
    // 优先演示曲库映射（同步、不发请求），再回源补详情；都没有就用 songKey
    final catalogSongs = ref.watch(catalogSongsProvider);
    final resolved = catalogSongs[task.songKey] ??
        ref.watch(songByIdProvider(task.songKey)).value;
    final title = resolved != null && resolved.title.isNotEmpty
        ? resolved.title
        : task.songKey;
    final state = switch (task.status) {
      DownloadStatus.pending => '等待中',
      DownloadStatus.downloading => '下载中',
      DownloadStatus.completed => '已完成',
      DownloadStatus.cancelled => '已取消',
      DownloadStatus.failed => '已失败',
    };
    final pct = (task.progress.clamp(0, 1) * 100).round();
    // 任务只记 songKey：解析不出 Song 时（源被删/停用）重试无从下手，这里直说
    final unresolved = resolved == null && task.status != DownloadStatus.downloading;
    final subtitle = task.error ??
        (task.status == DownloadStatus.downloading
            ? '下载中 $pct%'
            : (task.localPath ?? ''));

    return Padding(
      padding: const EdgeInsets.all(UiV2Spacing.s3),
      child: Row(
        children: [
          // 能用 Song 解析出封面就显示封面，否则退回音符占位
          UiV2Cover(source: resolved?.coverUrl, size: 42),
          const SizedBox(width: UiV2Spacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: UiV2Text.trackTitle.copyWith(color: t.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: UiV2Text.hint.copyWith(color: t.textDim),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: UiV2Radii.brPill,
                  child: SizedBox(
                    height: 4,
                    child: Stack(
                      children: [
                        Container(color: t.surface3),
                        FractionallySizedBox(
                          widthFactor: task.progress.clamp(0.0, 1.0),
                          child: Container(color: t.accent),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  state,
                  style: UiV2Text.hint.copyWith(color: t.textDim),
                ),
                if (unresolved)
                  Text(
                    '来源里找不到这首曲子，重试不可用',
                    style: UiV2Text.hint.copyWith(color: t.warn),
                  ),
              ],
            ),
          ),
          const SizedBox(width: UiV2Spacing.s3),
          switch (task.status) {
            DownloadStatus.downloading ||
            DownloadStatus.pending =>
              UiV2GhostMini(
                label: '取消',
                onTap: () async {
                  await actions.cancel(task.songKey);
                  if (context.mounted) {
                    showUiV2Toast(context, '已取消「$title」的下载');
                  }
                },
              ),
            DownloadStatus.completed => UiV2GhostMini(
                label: '删除缓存',
                danger: true,
                onTap: () async {
                  await actions.deleteCache(task.songKey);
                  if (context.mounted) {
                    showUiV2Toast(context, '已删除「$title」的缓存');
                  }
                },
              ),
            // 重试要能拿到 Song（DownloadManager.download 需要完整曲目）；
            // 解析不到时禁用按钮并说明原因，而不是假装开始下载
            _ => UiV2GhostMini(
                label: '重试',
                onTap: resolved == null
                    ? null
                    : () async {
                        await actions.retry(resolved);
                        if (context.mounted) {
                          showUiV2Toast(context, '已重新开始下载「$title」');
                        }
                      },
              ),
          },
        ],
      ),
    );
  }
}
