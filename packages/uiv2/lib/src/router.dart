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

import 'app_router.dart';

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
  'playlist': '歌单',
  'playlists': '歌单',
  'folder': '文件夹',
  'settings': '设置',
};

/// 无来路时，二级页高亮的所属栏目（原型 NAV_FOR 的“层级口径”）
///
/// 真实高亮优先走 [activeBranch]（跟随历史来路）；本表只用于**没有历史**的
/// 直接深链/冷启动进入（否则 liked/local 在移动端没有对应 tab，会出现无高亮）。
const Map<String, String> kBranchFallback = {
  'liked': 'profile',
  'local': 'library',
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

  /// 记录一次「访问下一页」，返回新状态
  ///
  /// 混合返回模型：
  ///   * 切到四个底部 tab（kRootMobile）→ 清空历史：根页没有返回键，
  ///     留着历史只会让“先点 tab 再进二级页”的返回点不可预期；
  ///   * 其余（二级页、移动端仅侧栏可见的 liked/local）→ 把当前页压入历史，
  ///     返回时逐级回上一页；跨分支进入时，历史里天然存着来源页。
  /// 历史上限，防止异常循环导航把状态无限增长。
  static const int _maxTrail = 20;

  NavState visit(NavEntry next) {
    if (next == current) return this;
    final trail2 = kRootMobile.contains(next.name)
        ? const <NavEntry>[]
        : <NavEntry>[...trail, current];
    if (trail2.length > _maxTrail) trail2.removeAt(0);
    return NavState(current: next, trail: trail2);
  }

  /// 取「上一页」对应的状态（历史存在时），否则 null
  NavState? backTarget() {
    if (trail.isEmpty) return null;
    return NavState(
      current: trail.last,
      trail: trail.sublist(0, trail.length - 1),
    );
  }
}

/// 当前页在侧栏/底栏应高亮的分支
///
/// 混合返回模型下高亮必须与“返回落点”一致，否则会出现
/// 「高亮首页、返回去我的」这种割裂：
///   * 一级页（移动端 kRootMobile / 桌面 kRootWide）→ 高亮自己；
///   * 二级页/移动端 liked、local → 优先高亮**历史来路**的分支；
///   * 没有来路（深链/冷启动）→ 回落到所属分支，移动端 liked/local 用回退表。
String activeBranch(NavState nav, {required bool wide}) {
  final name = nav.current.name;
  final isRoot = wide ? kRootWide.contains(name) : kRootMobile.contains(name);
  if (isRoot) return name;
  if (nav.trail.isEmpty) return kBranchFallback[name] ?? branchOf(name);
  return branchOf(nav.trail.last.name);
}

/// 导航 Notifier —— **门面**：对外仍是 go / back + NavState，内部交给 go_router。
///
/// 为什么保留这层：全项目 52 处调用点都只认 navProvider.go/back，
/// 直接改成 context.go / context.pop 会把路由细节散到每个页面里；
/// 门面让「页面只关心去哪」和「路由怎么实现」分开，迁移 go_router 时零改动。
class NavNotifier extends Notifier<NavState> {
  @override
  NavState build() {
    final router = ref.watch(appRouterProvider);
    // go_router 是唯一事实来源：路由一变就把当前条目同步过来（标题/返回键/底栏都用它）
    void sync() {
      final entry = navEntryFromUri(
        router.routerDelegate.currentConfiguration.uri,
      );
      // 只更新当前条目，保留 trail（返回栈由 visit/backTarget 维护）
      if (entry != state.current) {
        state = state.copyWith(current: entry);
      }
    }

    router.routerDelegate.addListener(sync);
    ref.onDispose(() => router.routerDelegate.removeListener(sync));
    return NavState(
      current: navEntryFromUri(router.routerDelegate.currentConfiguration.uri),
    );
  }

  /// 跳转到指定路由
  ///
  /// 一级页用 go（切分支、清掉该分支的栈，等价原型里一级页之间不产生层级）；
  /// 二级页用 push（压在该分支的 Navigator 上，返回键能回去）。
  void go(String name, [String param = '']) {
    final entry = NavEntry(name, param);
    if (entry == state.current) return;
    // 先落历史再导航：路由监听回调只会改 current，不会动 trail
    state = state.copyWith(trail: state.visit(entry).trail);
    final router = ref.read(appRouterProvider);
    final location = locationFor(name, param, wide: ref.read(layoutWideProvider));
    // 一律用 go：go_router 按路径重建匹配栈（shell → 分支 → 二级页），
    // 返回时 pop 回分支根，语义与原来「二级页压栈、返回退回上一级」一致。
    // 不用 push：命令式压栈不会更新 currentConfiguration.uri，
    // 顶栏标题/返回键这些依赖当前位置的地方会停在旧值（实测踩过）。
    router.go(location);
  }

  /// 返回上一页；没有来路时退到该页的上一级，再没有就回首页
  void back() {
    final router = ref.read(appRouterProvider);
    // 有历史：返回上一页（跨分支时即“来路页”），不依赖路由自身 pop 栈
    final prev = state.backTarget();
    if (prev != null) {
      state = prev;
      router.go(locationFor(prev.current.name, prev.current.param, wide: ref.read(layoutWideProvider)));
      return;
    }
    if (router.canPop()) {
      router.pop();
      return;
    }
    final parent = kParentRoute[state.current.name] ?? 'home';
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


/// 当前布局是否宽屏（壳工程在 build 里写；用于 liked/local 的路径选择）
class LayoutWideNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  set(bool value) => state = value;
}

final layoutWideProvider =
    NotifierProvider<LayoutWideNotifier, bool>(LayoutWideNotifier.new);

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
///
/// 兜底**不能**是"未找到"这种吓人文案：新加路由忘了登记标题时，
/// 手机上顶部会直接显示「未找到」（真实踩过：歌单详情的 playlist 漏登记）。
/// 取不到就返回空串，让顶部栏按"没有标题"处理。
String titleOf(NavEntry entry, {String? override}) {
  if (override != null && override.isNotEmpty) return override;
  return kRouteTitles[entry.name] ?? '';
}
