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

import '../components/now_playing.dart';
import '../components/player_bar.dart';
import '../components/shell_parts.dart';
import '../components/sheets.dart';
import '../components/rows.dart';
import '../components/surfaces.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../pages/downloads_page.dart';
import '../pages/folder_page.dart';
import '../pages/home_page.dart';
import '../pages/library_page.dart';
import '../pages/liked_page.dart';
import '../pages/local_page.dart';
import '../pages/logs_page.dart';
import '../pages/playlist_page.dart';
import '../pages/playlists_page.dart';
import '../pages/profile_page.dart';
import '../pages/recent_page.dart';
import '../pages/search_page.dart';
import '../pages/settings_page.dart';
import '../pages/sources_page.dart';
import '../pages/subs_page.dart';
import '../providers/providers.dart';
import '../router.dart';
import '../widgets/page_shell.dart';

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
  /// 构造外壳
  const UiV2AppShell({super.key});

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
              Positioned.fill(child: _RoutedView(nav: nav)),
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

/// 路由分发：一级页常驻 IndexedStack，二级页**叠在它上面**
///
/// 为什么不是"二级页替换一级页"：那样进「下载任务 / 设置 / 歌单」时，
/// 当前一级页面（比如「我的」）整棵子树会被 dispose，返回后滚动位置、
/// 展开状态全部重置 —— 用户实测就是"返回后滚动条回到最顶"。
/// 现在一级页始终挂载，二级页用 Stack 覆盖上去，返回即恢复原样。
class _RoutedView extends StatelessWidget {
  final NavState nav;

  const _RoutedView({required this.nav});

  @override
  Widget build(BuildContext context) {
    final onRoot = isRootRoute(nav.current.name);
    // 二级页下面该露出哪个一级页：取来路里最近的一级路由（没有则首页）
    final base = onRoot
        ? nav.current
        : ([...nav.trail.reversed].firstWhere(
            (e) => isRootRoute(e.name),
            orElse: () => const NavEntry('home'),
          ));

    final roots = IndexedStack(
      index: rootIndexOf(base.name),
      children: const [
        HomePage(),
        SearchPage(),
        LibraryPage(),
        LikedPage(),
        LocalPage(),
        ProfilePage(),
      ],
    );

    if (onRoot) return roots;
    return Stack(
      children: [
        Positioned.fill(child: roots),
        Positioned.fill(
          // 二级页必须自带不透明底色：它现在是叠在一级页之上的，
          // PageShell 自己不画背景，不铺底色就会把下面的首页透出来（真机预览踩过）
          child: ColoredBox(
            color: UiV2Theme.of(context).bg,
            child: KeyedSubtree(
              key: ValueKey(nav.current.key),
              child: _buildSub(nav.current),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSub(NavEntry entry) {
    return switch (entry.name) {
      'playlist' => PlaylistPage(playlistId: entry.param),
      'playlists' => const PlaylistsPage(),
      'folder' => FolderPage(folderName: entry.param),
      'recent' => const RecentPage(),
      'downloads' => const DownloadsPage(),
      'sources' => const SourcesPage(),
      'subs' => const SubsPage(),
      'logs' => const LogsPage(),
      'settings' => const SettingsPage(),
      // 未知路由：给出与原型 notFound 一致的引导
      _ => PageShell(
          child: UiV2Panel(
            child: UiV2Empty(
              title: '页面走丢了',
              text: '链接可能已失效，回到首页继续浏览。',
              icon: UiV2Icons.info,
              actions: Builder(
                builder: (context) => UiV2Button(
                  label: '回到首页',
                  variant: UiV2ButtonVariant.primary,
                  onTap: () => ProviderScope.containerOf(context, listen: false)
                      .read(navProvider.notifier)
                      .go('home'),
                ),
              ),
            ),
          ),
        ),
    };
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
