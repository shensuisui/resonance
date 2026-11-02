/// 应用外壳 —— 原型的 .app 栅格（sidebar / main / player / tabs）在 Flutter 的等价实现。
///
/// 断点口径（与 styles.css 完全一致）：
///   ≥768  侧栏出现、底部导航隐藏、播放条一行三区
///   ≥1024 侧栏展开成 264px、顶栏消失、返回键移到侧栏品牌行
///   768–1023 浮动返回键（left = 88 + 16），内容区上留白 72
///   768–1180 播放条按平板口径（隐藏歌名与音量组）
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../components/now_playing.dart';
import '../components/player_bar.dart';
import '../components/shell_parts.dart';
import '../components/sheets.dart';
import '../components/rows.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../providers/providers.dart';
import '../router.dart';

/// 当前页面标题
///
/// 二级页的标题以前只有固定表（歌单详情显示成「歌单」）。这里让"歌单详情"
/// 用**真实歌单名**：顶部标题栏就不再需要一个占高度的页面内标题。
/// 放在外壳而不是 providers：只有这里同时知道路由与歌单数据，
/// 让 providers 反向依赖 router 会形成循环。
final pageTitleProvider = Provider<String>((ref) {
  final entry = ref.watch(navProvider).current;
  if (entry.name == 'playlist') {
    final list = ref.watch(playlistsProvider).value ?? const <Playlist>[];
    for (final p in list) {
      if (p.id == entry.param) return p.name;
    }
  }
  return titleOf(entry);
});

/// 应用外壳
class UiV2AppShell extends ConsumerWidget {
  /// go_router 的分支容器（6 个一级页的 IndexedStack，保活由框架负责）
  final StatefulNavigationShell navigationShell;

  /// 构造外壳
  const UiV2AppShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 保活：播放器三路事件流（进度 / 时长 / 播放态）与曲库
    ref.watch(playerStreamBindingProvider);
    // 启动恢复：上次的队列 + 曲目 + 进度（暂停着，不出声）
    ref.watch(startupResumeProvider);
    ref.watch(themeModeProvider);
    ref.watch(catalogProvider);

    final nav = ref.watch(navProvider);
    final width = MediaQuery.sizeOf(context).width;
    final height = MediaQuery.sizeOf(context).height;
    final wide = width >= UiV2Breakpoints.wide;
    final desktop = width >= UiV2Breakpoints.desktop;
    final tablet = wide && width <= UiV2Breakpoints.tabletMax;

    final isRoot = kRootWide.contains(nav.current.name);
    final showBack = wide ? !isRoot : !kRootMobile.contains(nav.current.name);
    final title = ref.watch(pageTitleProvider);

    // 栅格（原型 .app）：纵向 = [上区 | 播放条 | 底栏]，上区 = [侧栏 | 内容]。
    // 两个要点：
    //   1) 播放条必须是**通栏**，所以它在上区之外，不放进内容列；
    //   2) 上区用 Row + stretch，侧栏才会占满「播放条以上」的整段高度
    //      （Row 默认 crossAxisAlignment 是 center，只给宽度的侧栏会被垂直居中成一条）。
    final content = Column(
      children: [
        if (!wide) UiV2TopBar(title: title, showBack: showBack),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: navigationShell),
              if (wide && width < UiV2Breakpoints.desktop && showBack)
                Positioned(
                  left: UiV2Spacing.s4,
                  top: UiV2Spacing.s4,
                  child: _FloatBack(
                    onTap: () => ref.read(navProvider.notifier).back(),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    final main = Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                UiV2Sidebar(expanded: desktop, showBack: showBack && desktop),
              Expanded(child: content),
            ],
          ),
        ),
        UiV2PlayerBar(wide: wide, tablet: tablet),
        if (!wide && kRootMobile.contains(nav.current.name))
          const UiV2TabBar(),
      ],
    );

    return Material(
      color: UiV2Theme.of(context).bg,
      child: Stack(
        children: [
          Positioned.fill(
            child: SizedBox(width: width, height: height, child: main),
          ),
          const UiV2NowPlayingOverlay(),
          UiV2ToastHost(
            bottomOffset: UiV2Metrics.playerBarHeight + (wide ? 60 : 76),
          ),
        ],
      ),
    );
  }
}


/// 平板浮动返回键（.float-back）
class _FloatBack extends StatelessWidget {
  final VoidCallback onTap;

  const _FloatBack({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface2,
        border: Border.all(color: t.lineStrong),
        borderRadius: UiV2Radii.brPill,
        boxShadow: t.shadow1,
      ),
      child: UiV2IconButton(
        icon: UiV2Icons.arrowLeft,
        semanticLabel: '返回',
        onTap: onTap,
      ),
    );
  }
}
