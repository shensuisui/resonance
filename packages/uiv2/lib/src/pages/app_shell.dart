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
import 'package:flutter/services.dart';
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
class UiV2AppShell extends ConsumerStatefulWidget {
  /// go_router 的分支容器（6 个一级页的 IndexedStack，保活由框架负责）
  final StatefulNavigationShell navigationShell;

  /// 构造外壳
  const UiV2AppShell({super.key, required this.navigationShell});

  @override
  ConsumerState<UiV2AppShell> createState() => _UiV2AppShellState();
}

class _UiV2AppShellState extends ConsumerState<UiV2AppShell> {
  /// 上一次按系统返回键的时间（一级页「再按一次退出」用）
  DateTime? _lastBackAt;

  @override
  Widget build(BuildContext context) {
    // 保活：播放器三路事件流（进度 / 时长 / 播放态）与曲库
    ref.watch(playerStreamBindingProvider);
    // 启动恢复：上次的队列 + 曲目 + 进度（暂停着，不出声）
    ref.watch(startupResumeProvider);
    ref.watch(themeModeProvider);
    ref.watch(catalogProvider);

    final nav = ref.watch(navProvider);
    final width = MediaQuery.sizeOf(context).width;
    final height = MediaQuery.sizeOf(context).height;
    final topInset = MediaQuery.paddingOf(context).top;
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
        // 窄屏顶栏自带状态栏安全区；宽屏没有顶栏，这里整体让出状态栏高度
        // （安卓平板/横屏窗口画到状态栏底下，Issue #5 第 2 条）
        if (!wide)
          UiV2TopBar(title: title, showBack: showBack)
        else if (topInset > 0)
          SizedBox(height: topInset),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: widget.navigationShell),
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 状态栏/导航栏样式跟着主题走：深色界面配浅色图标（否则深底深字看不见），
      // 底色保持透明让内容延伸到系统栏后面（edge-to-edge 下系统栏只是悬浮层）。
      value: (Theme.of(context).brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark)
          .copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: PopScope(
        // 系统返回键统一在这里接管：弹出浮层/二级页时轮不到它（路由在更上层），
        // 轮到它说明当前是一级页 —— 不能一声不吭把 App 退掉（Issue #5 第 3 条）。
        canPop: false,
        onPopInvokedWithResult: _handleSystemBack,
        child: Material(
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
        ),
      ),
    );
  }

  /// 系统返回键（安卓返回手势/返回键）的统一入口
  ///
  /// 弹层与二级页在更上层，返回键由它们自己消费，轮到这里只有三种情况：
  ///   1. 沉浸播放页开着 —— 返回键收起它（对应顶栏箭头/下滑手势）；
  ///   2. 移动端二级页（我喜欢的音乐/本地音乐等一级分支）—— 没有来路时
  ///      退到上一级（与顶栏返回键同一条 [NavNotifier.back] 路径）；
  ///   3. 一级页 —— 「再按一次返回键退出」：第一按只提示，两秒内再按才退出。
  Future<void> _handleSystemBack(bool didPop, Object? result) async {
    if (didPop) return;
    // 1) 沉浸播放页优先：它盖着整个外壳，返回键的第一直觉就是「收起这层」
    if (ref.read(nowPlayingProvider)) {
      ref.read(nowPlayingProvider.notifier).close();
      return;
    }
    // 2) 移动端二级页：退到上一级而不是退出 App
    if (!kRootMobile.contains(ref.read(navProvider).current.name)) {
      ref.read(navProvider.notifier).back();
      return;
    }
    // 3) 一级页：两秒内连按两次才真正退出
    final now = DateTime.now();
    if (_lastBackAt != null &&
        now.difference(_lastBackAt!) < const Duration(seconds: 2)) {
      await SystemNavigator.pop();
      return;
    }
    _lastBackAt = now;
    if (mounted) showUiV2Toast(context, '再按一次返回键退出');
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
