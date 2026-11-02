/// 应用外壳 —— 原型的 .app 栅格（sidebar / main / player / tabs）在 Flutter 的等价实现。
///
/// 断点口径（与 styles.css 完全一致）：
///   ≥768  侧栏出现、底部导航隐藏、播放条一行三区
///   ≥1024 侧栏展开成 264px、顶栏消失、返回键移到侧栏品牌行
///   768–1023 浮动返回键（left = 88 + 16），内容区上留白 72
///   768–1180 播放条按平板口径（隐藏歌名与音量组）
library;

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
    final title = titleOf(nav.current);

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

/// 路由分发：一级页走 IndexedStack（保留状态），二级页按需构建
class _RoutedView extends StatelessWidget {
  final NavState nav;

  const _RoutedView({required this.nav});

  @override
  Widget build(BuildContext context) {
    // 六个一级页面统一走 IndexedStack：切换时保留各自的滚动位置与状态
    if (isRootRoute(nav.current.name)) {
      return IndexedStack(
        index: rootIndexOf(nav.current.name),
        children: const [
          HomePage(),
          SearchPage(),
          LibraryPage(),
          LikedPage(),
          LocalPage(),
          ProfilePage(),
        ],
      );
    }
    return KeyedSubtree(
      key: ValueKey(nav.current.key),
      child: _buildSub(nav.current),
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
