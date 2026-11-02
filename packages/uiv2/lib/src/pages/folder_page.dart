/// 文件夹详情（原型 renderFolder）—— 文件夹名即路由参数
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/rows.dart';
import '../components/surfaces.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../providers/providers.dart';
import '../router.dart';
import '../widgets/page_shell.dart';
import 'local_page.dart';

/// 文件夹详情页（[folderName] 来自 localFoldersProvider 的分组名）
class FolderPage extends ConsumerWidget {
  /// 文件夹名
  final String folderName;

  /// 构造页面
  const FolderPage({super.key, required this.folderName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(localFoldersProvider);
    final folder = folders.where((f) => f.name == folderName).firstOrNull;
    if (folder == null) {
      return PageShell(
        child: UiV2Panel(
          child: UiV2Empty(
            title: '这个文件夹不在本地库里',
            text: '可能已被移除或尚未重新扫描，回到本地音乐看看。',
            icon: UiV2Icons.info,
            actions: UiV2Button(
              label: '回到本地音乐',
              variant: UiV2ButtonVariant.primary,
              onTap: () => ref.read(navProvider.notifier).go('local'),
            ),
          ),
        ),
      );
    }

    final t = UiV2Theme.of(context);
    return PageShell(
      topPadding: UiV2Spacing.s4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: UiV2Spacing.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(folder.name, style: UiV2Text.sectionTitle.copyWith(color: t.text)),
                const SizedBox(height: UiV2Spacing.s2),
                Text(
                  '${folder.songs.length} 首 · '
                      '${folder.totalDuration.inMinutes} 分钟',
                  style: UiV2Text.bodyDim.copyWith(color: t.textDim),
                ),
              ],
            ),
          ),
          UiV2Panel(
            child: UiV2TrackList(
              rows: [
                for (var i = 0; i < folder.songs.length; i++)
                  localTrackRow(context, ref, folder.songs[i], i, folder.songs),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
