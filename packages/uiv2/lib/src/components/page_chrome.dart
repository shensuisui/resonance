/// 移动端页面级顶栏（顶栏下沉到页面，随路由一起做转场）
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../router.dart';
import 'shell_parts.dart';

/// 自带 PageHead 大标题的页面：顶栏不再重复显示标题
const Set<String> kPageHeadRoutes = <String>{
  'home',
  'search',
  'library',
  'liked',
  'local',
  'recent',
  'downloads',
  'playlist',
  'playlists',
  'sources',
  'subs',
  'logs',
  'settings',
};

/// 移动端页面标题（歌单详情用真实歌单名）
final mobilePageTitleProvider = Provider<String>((ref) {
  final entry = ref.watch(navProvider).current;
  if (entry.name == 'playlist') {
    final list = ref.watch(playlistsProvider).value ?? const <Playlist>[];
    for (final p in list) {
      if (p.id == entry.param) return p.name;
    }
  }
  return titleOf(entry);
});

/// 窄屏页面外壳：顶栏 + 页面内容
///
/// 顶栏放在这里（而不是应用外壳）后，它会跟页面一起被卡片推入/淡入，
/// 不再出现「AppBar 瞬换、内容在动」的割裂。
class UiV2MobilePageChrome extends ConsumerWidget {
  /// 页面内容
  final Widget child;

  /// 构造
  const UiV2MobilePageChrome({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(navProvider);
    final name = nav.current.name;
    final hasPageHead = kPageHeadRoutes.contains(name);
    final showBack = !kRootMobile.contains(name);
    return Column(
      children: [
        UiV2TopBar(
          title: hasPageHead ? '' : ref.watch(mobilePageTitleProvider),
          showBack: showBack,
          showTitle: !hasPageHead,
        ),
        Expanded(child: child),
      ],
    );
  }
}
