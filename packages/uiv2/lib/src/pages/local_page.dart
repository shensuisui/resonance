/// 本地音乐（原型 renderLocal / renderFolder）—— 数据来自真实扫描源
///
/// 分组规则：按 `Song.localPath` 的父目录名分组（providers.localFoldersProvider）。
/// 扫描动作走 `ScanNotifier`（写 settings 的 scan_dir 后调 LocalScanSource）。
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
import '../widgets/track_actions.dart';

/// 本地音乐页
class LocalPage extends ConsumerWidget {
  /// 构造页面
  const LocalPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(localFoldersProvider);
    final scanDir = ref.watch(scanDirProvider).value;
    final totalSongs = folders.fold<int>(0, (sum, f) => sum + f.songs.length);
    final totalDuration = folders.fold<Duration>(
      Duration.zero,
      (sum, f) => sum + f.totalDuration,
    );

    return PageShell(
      topPadding: UiV2Spacing.s4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(
            title: '本地音乐',
            sub: totalSongs == 0
                ? '扫描本机文件夹后，音频文件会按目录分组显示在这里。'
                : '$totalSongs 首 · ${folders.length} 个文件夹 · '
                    '${_fmtLong(totalDuration)} · 不消耗流量',
            action: UiV2Button(
              label: '扫描文件夹',
              icon: UiV2Icons.folder,
              variant: UiV2ButtonVariant.soft,
              onTap: () => _scan(context, ref, scanDir),
            ),
          ),
          if (folders.isEmpty)
            UiV2Panel(
              child: UiV2Empty(
                title: '还没有本地音乐',
                text: '选择一个文件夹，回响会扫描其中的音频文件，按文件夹分组。'
                    '扫描目录：${scanDir == null || scanDir.isEmpty ? '未设置' : scanDir}',
                icon: UiV2Icons.folder,
                actions: UiV2Button(
                  label: '选择文件夹',
                  variant: UiV2ButtonVariant.primary,
                  onTap: () => _scan(context, ref, scanDir),
                ),
              ),
            )
          else
            UiV2Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < folders.length; i++)
                    UiV2ListRow(
                      label: folders[i].name,
                      hint:
                          '${folders[i].songs.length} 首 · ${_fmtLong(folders[i].totalDuration)}',
                      leading: const UiV2FolderIcon(),
                      trailing: const UiV2Chevron(),
                      divider: i < folders.length - 1,
                      onTap: () => ref
                          .read(navProvider.notifier)
                          .go('folder', folders[i].name),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 触发扫描：目录未设置时弹输入框；已设置直接扫
  Future<void> _scan(BuildContext context, WidgetRef ref, String? scanDir) async {
    if (scanDir == null || scanDir.isEmpty) {
      await _pickAndScan(context, ref, null);
      return;
    }
    await ref.read(scanProvider.notifier).scan();
    if (context.mounted) {
      final s = ref.read(scanProvider);
      showUiV2Toast(
        context,
        s.error != null ? '扫描失败：${s.error}' : '已登记 ${s.foundCount ?? 0} 个本地文件',
      );
    }
  }

  /// 输入扫描目录（桌面端手输路径；uiv2 不引入 file_picker 平台依赖）
  static Future<void> _pickAndScan(
    BuildContext context,
    WidgetRef ref,
    String? current,
  ) async {
    final controller = TextEditingController(text: current ?? '');
    await showUiV2Sheet(
      context,
      title: '扫描目录',
      child: Builder(
        builder: (sheetContext) {
          final t = UiV2Theme.of(sheetContext);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '填写本机绝对路径，例如 D:\\Music。扫描只读取文件名、时长与同名 .lrc，不上传任何内容。',
                style: UiV2Text.hint.copyWith(color: t.textDim),
              ),
              const SizedBox(height: UiV2Spacing.s3),
              TextField(
                controller: controller,
                autofocus: true,
                style: UiV2Text.body.copyWith(color: t.text),
                decoration: InputDecoration(
                  hintText: 'D:\\Music',
                  hintStyle: UiV2Text.body.copyWith(color: t.textMute),
                  filled: true,
                  fillColor: t.surface2,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: UiV2Spacing.s4,
                    vertical: UiV2Spacing.s3,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: UiV2Radii.brMd,
                    borderSide: BorderSide(color: t.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: UiV2Radii.brMd,
                    borderSide: BorderSide(color: t.line),
                  ),
                ),
              ),
              const SizedBox(height: UiV2Spacing.s4),
              UiV2Button(
                label: '保存并扫描',
                icon: UiV2Icons.check,
                variant: UiV2ButtonVariant.primary,
                block: true,
                onTap: () async {
                  final path = controller.text.trim();
                  if (path.isEmpty) {
                    showUiV2Toast(sheetContext, '请输入目录路径');
                    return;
                  }
                  Navigator.of(sheetContext).maybePop();
                  await ref.read(scanProvider.notifier).scanDirectory(path);
                  if (context.mounted) {
                    final s = ref.read(scanProvider);
                    showUiV2Toast(
                      context,
                      s.error != null
                          ? '扫描失败：${s.error}'
                          : '已登记 ${s.foundCount ?? 0} 个本地文件',
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 秒 → 「H 小时 M 分 / M 分钟」
String _fmtLong(Duration d) {
  final minutes = d.inMinutes;
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return h > 0 ? '$h 小时 $m 分' : '$m 分钟';
}

/// 本地曲目行（复用统一曲目行；meta 传 null —— 本地曲目不在演示配表里）
Widget localTrackRow(
  BuildContext context,
  WidgetRef ref,
  Song song,
  int index,
) {
  return UiV2SongRow(
    song: song,
    index: index,
    showArt: song.coverUrl != null && song.coverUrl!.isNotEmpty,
    subtitleOverride: song.artist.isEmpty ? '本地文件' : null,
    sourceNameOverride: '本地',
    onTap: () => TrackActions.play(context, ref, song),
    onToggleLike: () => TrackActions.toggleLike(context, ref, song),
    onMore: () => showTrackMenu(context, song: song),
  );
}
