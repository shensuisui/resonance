/// 应用主壳 —— 底部导航 + 页面切换 + 迷你播放器

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/mini_player.dart';
import 'search_page.dart';
import 'recent_plays_page.dart';
import 'playlist_list_page.dart';
import 'source_management_page.dart';
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
    SourceManagementPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (i) => setState(() => _currentIndex = i),
            destinations: const [
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
                icon: Icon(Icons.cloud_rounded),
                label: '源',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_rounded),
                label: '设置',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
