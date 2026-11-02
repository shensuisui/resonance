/// 最近播放（原型 renderRecent）
///
/// 数据来源：[recentSongsProvider] —— RecentPlaysService 的真实记录快照
/// （服务内部负责去重移顶与上限清理），页面不再从配表取曲目。
/// 顶部提供「清空最近播放」，直接调用 [recentProvider].clear()。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/rows.dart';
import '../components/sheets.dart';
import '../components/surfaces.dart';
import '../design/icons.dart';
import '../providers/providers.dart';
import '../router.dart';
import '../widgets/page_shell.dart';
import '../widgets/track_actions.dart';

/// 最近播放页
class RecentPage extends ConsumerWidget {
  /// 构造页面
  const RecentPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(recentSongsProvider);
    // 展示元数据：封面 / 时长（记录快照里没有时长）
    final meta = ref.watch(catalogTracksProvider);
    final count = songs.length;

    return PageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(
            title: '最近播放',
            sub: count == 0
                ? ''
                : '共 $count 首 · 上限 $kRecentPlaysMaxCount 首，重复播放会移到最前',
            action: count == 0
                ? null
                : UiV2Button(
                    label: '清空最近播放',
                    icon: UiV2Icons.trash,
                    variant: UiV2ButtonVariant.soft,
                    onTap: () => _clear(context, ref),
                  ),
          ),
          if (songs.isEmpty)
            UiV2Panel(
              child: UiV2Empty(
                title: '还没有最近播放',
                text: '点开任意一首歌，它会自动出现在这里。',
                icon: UiV2Icons.clock,
                actions: UiV2Button(
                  label: '去首页看看',
                  variant: UiV2ButtonVariant.primary,
                  onTap: () => ref.read(navProvider.notifier).go('home'),
                ),
              ),
            )
          else
            UiV2Panel(
              child: UiV2TrackList(
                rows: [
                  for (var i = 0; i < songs.length; i++)
                    UiV2SongRow(
                      song: songs[i],
                      meta: meta[songs[i].id],
                      index: i,
                      showArt: true,
                      onTap: () => TrackActions.playInQueue(context, ref,
                          TrackActions.recentQueue(songs), i),
                      onToggleLike: () =>
                          TrackActions.toggleLike(context, ref, songs[i]),
                      onMore: () =>
                          showTrackMenu(context, song: songs[i]),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 清空最近播放：调真实服务的 clear()，成功后给一次提示
  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    await ref.read(recentProvider.notifier).clear();
    if (!context.mounted) return;
    showUiV2Toast(context, '已清空最近播放');
  }
}
