/// 应用主壳 —— 底部导航 + 页面切换 + 迷你播放器

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../widgets/player_overlay.dart';
import 'search_page.dart';
import 'recent_plays_page.dart';
import 'playlist_list_page.dart';
import 'settings_page.dart';
import 'discover_page.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _currentIndex = 0;

  final _pages = const [
    SearchPage(),
    DiscoverPage(),
    RecentPlaysPage(),
    PlaylistListPage(),
    SettingsPage(),
  ];

  /// 底部导航目的地（窄屏竖屏）
  static const _barDestinations = [
    NavigationDestination(
      icon: Icon(Icons.search_rounded),
      label: '搜索',
    ),
    NavigationDestination(
      icon: Icon(Icons.explore_rounded),
      label: '发现',
    ),
    NavigationDestination(
      icon: Icon(Icons.history_rounded),
      label: '最近',
    ),
    NavigationDestination(
      icon: Icon(Icons.queue_music_rounded),
      label: '歌单',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_rounded),
      label: '设置',
    ),
  ];

  /// 侧边导航目的地（宽屏横屏）
  static const _railDestinations = [
    NavigationRailDestination(
      icon: Icon(Icons.search_rounded),
      label: Text('搜索'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.explore_rounded),
      label: Text('发现'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.history_rounded),
      label: Text('最近'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.queue_music_rounded),
      label: Text('歌单'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.settings_rounded),
      label: Text('设置'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // 保持播放器状态流绑定存活（进度条/歌词同步/播放按钮状态依赖此绑定）
    ref.watch(playerStreamBindingProvider);
    // 应用启动即加载本地插件与订阅（仅本地恢复，不访问网络）
    ref.watch(pluginLibraryProvider);
    ref.watch(subscriptionLibraryProvider);

    // 宽屏（横屏）用左侧导航栏，窄屏（竖屏）用底部导航栏
    return OrientationBuilder(
      builder: (context, orientation) {
        final isWide = orientation == Orientation.landscape;
        // 迷你条停靠位置：竖屏在底部导航上方，横屏贴底
        final navH = Theme.of(context).navigationBarTheme.height ?? 80;
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        final miniBarBottom = isWide ? 0.0 : navH + bottomInset;

        final main = isWide
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: _currentIndex,
                    onDestinationSelected: (i) =>
                        setState(() => _currentIndex = i),
                    labelType: NavigationRailLabelType.all,
                    destinations: _railDestinations,
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: IndexedStack(
                            index: _currentIndex,
                            children: _pages,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Scaffold(
                body: IndexedStack(
                  index: _currentIndex,
                  children: _pages,
                ),
                bottomNavigationBar: NavigationBar(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (i) =>
                      setState(() => _currentIndex = i),
                  destinations: _barDestinations,
                ),
              );

        // 主界面 + 播放器覆盖层（迷你条/全屏播放器拖动切换）
        return Stack(
          children: [
            Positioned.fill(child: main),
            PlayerOverlay(miniBarBottom: miniBarBottom),
          ],
        );
      },
    );
  }
}
