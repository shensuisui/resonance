/// 路由 —— 复刻原型 app.js 的 hash 路由（navTrail / PARENT_ROUTE / TITLES / NAV_FOR）。
///
/// 原型用 `#/name/param` 组织页面：
///   * 一级页面：大屏 6 个（home/search/library/liked/local/profile），
///     移动端 4 个（home/search/library/profile）；
///   * 二级页面：album/artist/playlist/folder/recent/downloads/sources/subs/logs/playlists；
///   * 返回键：有来路退回上一页，没有来路退到该页的上一级，再没有回首页。
///
/// Flutter 侧不引入路由库：一级页面用 IndexedStack 保留状态（对应原型同页重渲染），
/// 二级页面按当前条目重建（对应原型的 innerHTML 覆盖）。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 一条导航记录（路由名 + 参数）
@immutable
class NavEntry {
  /// 路由名（home / search / album …）
  final String name;

  /// 路由参数（专辑 id、艺人名、歌单 id …）
  final String param;

  /// 构造导航记录
  const NavEntry(this.name, [this.param = '']);

  /// 同一页面的唯一键（用于比较与去重）
  String get key => param.isEmpty ? name : '$name/$param';

  @override
  bool operator ==(Object other) =>
      other is NavEntry && other.name == name && other.param == param;

  @override
  int get hashCode => Object.hash(name, param);
}

/// 大屏的一级页面（原型 ROOT_WIDE）
const List<String> kRootWide = [
  'home', 'search', 'library', 'liked', 'local', 'profile',
];

/// 全部一级页面的规范顺序（IndexedStack 的下标按它计算）
///
/// 顺序固定：home / search / library / liked / local / profile。
/// 大屏六项全是一级；移动端只有前四个能在底部导航里到达，liked 与 local
/// 在移动端是二级页面（原型 ROOT_MOBILE 的口径），但它们仍可被 go() 直接打开。
const List<String> kRootRoutes = kRootWide;

/// 移动端的一级页面（原型 ROOT_MOBILE —— 底部导航只有四项）
const List<String> kRootMobile = ['home', 'search', 'library', 'profile'];

/// 该路由是否为一等页面（大屏口径）
bool isRootRoute(String name) => kRootRoutes.contains(name);

/// 二级页面的上一级（原型 PARENT_ROUTE）
const Map<String, String> kParentRoute = {
  'playlist': 'library',
  'playlists': 'library',
  'folder': 'local',
  'liked': 'profile',
  'recent': 'profile',
  'downloads': 'profile',
  'sources': 'profile',
  'subs': 'profile',
  'logs': 'profile',
  'settings': 'profile',
};

/// 页面标题（原型 TITLES）
const Map<String, String> kRouteTitles = {
  'home': '首页',
  'search': '搜索',
  'library': '音乐库',
  'liked': '我喜欢的音乐',
  'local': '本地音乐',
  'profile': '我的',
  'recent': '最近播放',
  'downloads': '下载任务',
  'sources': '音乐源',
  'subs': '订阅',
  'logs': '运行日志',
  'playlists': '歌单',
  'folder': '文件夹',
  'settings': '设置',
};

/// 页面 → 侧栏/底栏高亮项（原型 NAV_FOR）
const Map<String, String> kNavFor = {
  'liked': 'liked',
  'local': 'local',
  'playlist': 'library',
  'playlists': 'library',
  'recent': 'home',
  'downloads': 'profile',
  'sources': 'profile',
  'subs': 'profile',
  'logs': 'profile',
  'folder': 'local',
};

/// 侧栏/底栏目的地
@immutable
class NavDestination {
  /// 路由名
  final String route;

  /// 图标名（见 UiV2Icons）
  final String icon;

  /// 文案
  final String label;

  /// 构造目的地
  const NavDestination(this.route, this.icon, this.label);
}

/// 大屏侧栏目的地（原型 .nav__item 六项）
const List<NavDestination> kSidebarDestinations = [
  NavDestination('home', 'home', '首页'),
  NavDestination('search', 'search', '搜索'),
  NavDestination('library', 'library', '音乐库'),
  NavDestination('liked', 'heart', '我喜欢的音乐'),
  NavDestination('local', 'folder', '本地音乐'),
  NavDestination('profile', 'user', '我的'),
];

/// 移动端底部导航目的地（原型 .tab 四项）
const List<NavDestination> kTabDestinations = [
  NavDestination('home', 'home', '首页'),
  NavDestination('search', 'search', '搜索'),
  NavDestination('library', 'library', '音乐库'),
  NavDestination('profile', 'user', '我的'),
];

/// 当前导航状态：当前页 + 返回栈
class NavState {
  /// 当前页面
  final NavEntry current;

  /// 返回栈（不含当前页）
  final List<NavEntry> trail;

  /// 构造导航状态
  const NavState({required this.current, this.trail = const []});

  /// 复制并覆盖字段
  NavState copyWith({NavEntry? current, List<NavEntry>? trail}) =>
      NavState(current: current ?? this.current, trail: trail ?? this.trail);
}

/// 导航 Notifier —— 提供 go / back，语义与原型 navigate / goBack 一致。
class NavNotifier extends Notifier<NavState> {
  @override
  NavState build() => const NavState(current: NavEntry('home'));

  /// 跳转到指定路由
  ///
  /// 一级页面清空返回栈（原型里一级页面相互之间不产生返回层级）。
  void go(String name, [String param = '']) {
    final entry = NavEntry(name, param);
    if (entry == state.current) return;
    if (kRootWide.contains(name)) {
      state = NavState(current: entry);
      return;
    }
    state = NavState(
      current: entry,
      trail: [...state.trail, state.current],
    );
  }

  /// 返回上一页；没有来路时退到该页的上一级，再没有就回首页
  void back() {
    final cur = state.current;
    final trail = List.of(state.trail);
    while (trail.isNotEmpty && trail.last == cur) {
      trail.removeLast();
    }
    if (trail.isNotEmpty) {
      state = NavState(current: trail.removeLast(), trail: trail);
      return;
    }
    final parent = kParentRoute[cur.name] ?? 'home';
    go(parent);
  }

  /// 当前页面是否需要返回键
  ///
  /// 大屏一级页面不出（原型 isRootWide），移动端另有口径（[kRootMobile]）。
  bool needsBack(bool wideLayout) {
    final name = state.current.name;
    return wideLayout ? !kRootWide.contains(name) : !kRootMobile.contains(name);
  }
}

/// 导航状态 Provider
final navProvider = NotifierProvider<NavNotifier, NavState>(NavNotifier.new);

/// 一级页面下标（IndexedStack 用）
int rootIndexOf(String route) {
  // 必须与 app_shell 里 IndexedStack 的子项顺序（kRootRoutes，6 项）一致。
  // 历史缺陷：这里曾用 kRootMobile（只有 4 项 home/search/library/profile），
  // 于是 liked/local 取不到下标被回退成 0（显示首页），profile 取到 3（命中 LikedPage）。
  final index = kRootRoutes.indexOf(route);
  return index < 0 ? 0 : index;
}

/// 页面标题：优先页面数据（专辑名/歌单名），否则取固定标题表
String titleOf(NavEntry entry, {String? override}) {
  if (override != null && override.isNotEmpty) return override;
  return kRouteTitles[entry.name] ?? '未找到';
}
