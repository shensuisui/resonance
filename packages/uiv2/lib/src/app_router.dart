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

/// 路由页自带的不透明底色
///
/// 为什么必须有：go_router 的 CustomTransitionPage.opaque 默认 true，含义是
/// 「过渡**结束后**，后面那页就不再构建」—— 所以不带底色的页面静止时看着正常，
/// 但过渡**进行中**两页是同时绘制的，页面自己不画底色，上一页的内容就会透过来
/// （真机中间帧拍得很清楚：上一页的「听歌的人 / 免费账户·在线与本地同步」与
/// 设置页的标题叠在一起）。
///
/// 这层就是页面自己的不透明背景，和页面一起位移，因此不参与淡入。
class UiV2RouteSurface extends StatelessWidget {
  /// 子组件（页面内容）
  final Widget child;

  /// 构造路由页底色
  const UiV2RouteSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: UiV2Theme.of(context).bg, child: child);
}

/// 二级页转场的起始位移（纯函数，便于单测）
///
/// 规则按**窗口宽度**分两档（断点见 [UiV2Breakpoints.wide] = 768，平板也算大屏）：
///   * 窄屏：从右侧滑入（`Offset(0.12, 0)`）——手机上一页推进来是天然的层级隐喻；
///   * 宽屏/平板：只做**轻微上浮**（`Offset(0, 0.04)`），水平位移必须为 0。
///
/// 为什么宽屏不能横向滑：宽屏内容区很宽，横向位移会让整块内容「被推着走」，
/// 侧栏与播放条却纹丝不动，看起来像页面在壳子里滑动 —— 很突兀（用户指出过）。
Offset subPageSlideFrom(double width) => width >= UiV2Breakpoints.wide
    ? const Offset(0, 0.04)
    : const Offset(0.12, 0);

/// 二级页转场：位移（按屏宽分档）+ 淡入；一级页不转场，切 tab 要即时
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
          begin: subPageSlideFrom(MediaQuery.sizeOf(context).width),
          end: Offset.zero,
        ).animate(curved),
        // 底色铺实（不淡入），内容在实底色上淡入：
        // 若连底色一起淡入，过渡途中依旧能透出上一页的文字，等于没修
        child: UiV2RouteSurface(
          // 只在**进入**方向淡入；**退出**（出栈）方向整页原样滑走。
          // 同一根动画反向时 FadeTransition 会变成淡出，把整页内容先褪成白板
          // 再滑走 —— 就是用户报的「出栈时页面变白」。
          child: animation.status == AnimationStatus.reverse
              ? child
              : FadeTransition(opacity: curved, child: child),
        ),
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
