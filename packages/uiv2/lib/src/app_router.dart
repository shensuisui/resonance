/// 路由表（go_router）
///
/// 结构对应原来的手写路由：
///   * 6 个一级页 → StatefulShellRoute 的 6 个 branch（各自独立 Navigator，
///     切换 tab 不重建、滚动位置保留，等价原来的 IndexedStack）；
///   * 9 个二级页 → 挂在**所属一级页的分支**下面，push 到该分支的 Navigator 上，
///     所以它们渲染在内容区（播放条/侧栏/顶栏都还在），等价原来的 Stack 覆盖；
///   * 二级页统一带转场（右侧滑入 + 淡入），一级页保持即时切换。
///
/// 参数编码：一律走查询参数 p=（go_router 会解码），不用路径段 ——
/// 参数里有 ::（远端歌单 sourceId::playlistId）甚至斜杠，塞进路径会踩转义。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'design/tokens.dart';
import 'pages/app_shell.dart';
import 'pages/home_page.dart';
import 'pages/library_page.dart';
import 'pages/liked_page.dart';
import 'pages/local_page.dart';
import 'pages/folder_page.dart';
import 'pages/logs_page.dart';
import 'pages/playlist_page.dart';
import 'pages/playlists_page.dart';
import 'pages/profile_page.dart';
import 'pages/recent_page.dart';
import 'pages/downloads_page.dart';
import 'pages/search_page.dart';
import 'pages/settings_page.dart';
import 'pages/sources_page.dart';
import 'pages/subs_page.dart';
import 'router.dart';

/// 全局 Navigator key
///
/// 唯一用途：发版前集成检查的 recover 需要「关掉所有模态浮层」（sheet / dialog）。
/// 业务代码不依赖它；debug-only 扩展通过 uiV2DismissOverlays 调到根路由。
final GlobalKey<NavigatorState> uiV2NavigatorKey = GlobalKey<NavigatorState>();

/// 关掉所有模态浮层，回到根路由；返回是否执行成功
bool uiV2DismissOverlays() {
  final navigator = uiV2NavigatorKey.currentState;
  if (navigator == null) return false;
  navigator.popUntil((route) => route.isFirst);
  return true;
}

/// 一个路由的静态定义
@immutable
class RouteDef {
  /// 路由名（与 [NavEntry.name] 一致）
  final String name;

  /// 绝对路径
  final String path;

  /// 所属一级页（一级页自身为 null）
  final String? parent;

  /// 构造
  const RouteDef(this.name, this.path, {this.parent});
}

/// 全部路由
const List<RouteDef> kRouteDefs = [
  RouteDef('home', '/home'),
  RouteDef('search', '/search'),
  RouteDef('library', '/library'),
  RouteDef('liked', '/liked'),
  RouteDef('local', '/local'),
  RouteDef('profile', '/profile'),
  RouteDef('playlist', '/library/playlist', parent: 'library'),
  RouteDef('playlists', '/library/playlists', parent: 'library'),
  RouteDef('folder', '/local/folder', parent: 'local'),
  RouteDef('recent', '/profile/recent', parent: 'profile'),
  RouteDef('downloads', '/profile/downloads', parent: 'profile'),
  RouteDef('sources', '/profile/sources', parent: 'profile'),
  RouteDef('subs', '/profile/subs', parent: 'profile'),
  RouteDef('logs', '/profile/logs', parent: 'profile'),
  RouteDef('settings', '/profile/settings', parent: 'profile'),
];

/// 路由名 → 定义
final Map<String, RouteDef> kRouteDefByName = {
  for (final d in kRouteDefs) d.name: d,
};

/// 路径 → 路由名
final Map<String, String> kRouteNameByPath = {
  for (final d in kRouteDefs) d.path: d.name,
};

/// 该路由属于哪个一级页（一级页返回自身）
String branchOf(String name) => kRouteDefByName[name]?.parent ?? name;

/// 路由名 + 参数 → 位置字符串（参数走查询参数）
String locationOf(String name, [String param = '']) {
  final path = kRouteDefByName[name]?.path ?? '/home';
  if (param.isEmpty) return path;
  return path + '?p=' + Uri.encodeQueryComponent(param);
}

/// 位置字符串 → 导航记录
NavEntry navEntryFromUri(Uri uri) {
  final name = kRouteNameByPath[uri.path] ?? 'home';
  return NavEntry(name, uri.queryParameters['p'] ?? '');
}

/// 二级页转场：右侧滑入 + 淡入（一级页不转场，切 tab 要即时）
CustomTransitionPage<void> _subPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: UiV2Motion.d2,
    reverseTransitionDuration: UiV2Motion.d2,
    transitionsBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: UiV2Motion.enter,
        reverseCurve: UiV2Motion.exit,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.12, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

/// 一级页（无转场）
NoTransitionPage<void> _rootPage(GoRouterState state, Widget child) =>
    NoTransitionPage<void>(key: state.pageKey, child: child);

/// 取查询参数里的路由参数
String _param(GoRouterState state) => state.uri.queryParameters['p'] ?? '';

/// 路由实例
///
/// 用 Provider 持有，便于测试注入与释放；[uiV2NavigatorKey] 继续作为根 Navigator，
/// 使「关掉所有模态浮层」的调试能力保持不变。
final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    navigatorKey: uiV2NavigatorKey,
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            UiV2AppShell(navigationShell: navigationShell),
        branches: [
          _branch('/home', const HomePage()),
          _branch('/search', const SearchPage()),
          _branch('/library', const LibraryPage(), subs: [
            GoRoute(
              path: 'playlist',
              pageBuilder: (c, s) =>
                  _subPage(s, PlaylistPage(playlistId: _param(s))),
            ),
            GoRoute(
              path: 'playlists',
              pageBuilder: (c, s) => _subPage(s, const PlaylistsPage()),
            ),
          ]),
          _branch('/liked', const LikedPage()),
          _branch('/local', const LocalPage(), subs: [
            GoRoute(
              path: 'folder',
              pageBuilder: (c, s) =>
                  _subPage(s, FolderPage(folderName: _param(s))),
            ),
          ]),
          _branch('/profile', const ProfilePage(), subs: [
            GoRoute(
              path: 'recent',
              pageBuilder: (c, s) => _subPage(s, const RecentPage()),
            ),
            GoRoute(
              path: 'downloads',
              pageBuilder: (c, s) => _subPage(s, const DownloadsPage()),
            ),
            GoRoute(
              path: 'sources',
              pageBuilder: (c, s) => _subPage(s, const SourcesPage()),
            ),
            GoRoute(
              path: 'subs',
              pageBuilder: (c, s) => _subPage(s, const SubsPage()),
            ),
            GoRoute(
              path: 'logs',
              pageBuilder: (c, s) => _subPage(s, const LogsPage()),
            ),
            GoRoute(
              path: 'settings',
              pageBuilder: (c, s) => _subPage(s, const SettingsPage()),
            ),
          ]),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// 造一个一级页分支
StatefulShellBranch _branch(
  String path,
  Widget child, {
  List<RouteBase> subs = const [],
}) {
  return StatefulShellBranch(
    routes: [
      GoRoute(
        path: path,
        pageBuilder: (context, state) => _rootPage(state, child),
        routes: subs,
      ),
    ],
  );
}
