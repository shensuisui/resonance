/// 应用外壳的零件 —— 顶栏、侧栏（窄轨 / 完整）、底部导航。
/// 对应原型 index.html 的 .topbar / .sidebar / .tabbar 与相关断点规则。
library;

import 'dart:ui' show ImageFilter;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';

import 'brand_mark.dart';
import '../providers/providers.dart';
import '../router.dart';
import 'rows.dart';

/// 顶栏（.topbar）—— 仅移动端显示，含返回键、标题与右侧动作
class UiV2TopBar extends ConsumerWidget {
  /// 当前页面标题
  final String title;

  /// 是否显示返回键
  final bool showBack;

  /// 构造顶栏
  const UiV2TopBar({super.key, required this.title, required this.showBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    // color-mix(in srgb, var(--bg) 84%, transparent)：底色 84% 不透明 + 背景模糊
    final bg = t.bg.withValues(alpha: 0.84);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: UiV2Metrics.topBarHeight,
            maxHeight: UiV2Metrics.topBarHeight,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: UiV2Spacing.s3,
            vertical: UiV2Spacing.s2,
          ),
          decoration: BoxDecoration(
            color: bg,
            border: Border(bottom: BorderSide(color: t.line)),
          ),
          child: Row(
            children: [
              if (showBack)
                UiV2IconButton(
                  icon: UiV2Icons.arrowLeft,
                  semanticLabel: '返回',
                  onTap: () => ref.read(navProvider.notifier).back(),
                ),
              Expanded(
                child: Text(
                  title,
                  style: UiV2Text.topBarTitle.copyWith(color: t.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              UiV2IconButton(
                icon: UiV2Icons.search,
                semanticLabel: '搜索',
                onTap: () => ref.read(navProvider.notifier).go('search'),
              ),
              UiV2IconButton(
                icon: ref.watch(themeModeProvider) == ThemeMode.dark
                    ? UiV2Icons.sun
                    : UiV2Icons.moon,
                semanticLabel: '切换深浅色主题',
                onTap: () => ref.read(themeModeProvider.notifier).toggleDark(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 侧栏（.sidebar）—— 宽屏窄轨（88px）与桌面完整侧栏（264px）两种形态
class UiV2Sidebar extends ConsumerWidget {
  /// 是否展开（≥1024 为 true）
  final bool expanded;

  /// 是否显示返回键（品牌行右侧，仅展开形态）
  final bool showBack;

  /// 构造侧栏
  const UiV2Sidebar({super.key, required this.expanded, required this.showBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final nav = ref.watch(navProvider);
    final active = kNavFor[nav.current.name] ?? nav.current.name;
    // 侧栏「你的歌单」只列自建歌单（收藏的远端歌单只在音乐库「收藏歌单」分栏）
    final playlists = ref.watch(ownedPlaylistsProvider).value ?? const <Playlist>[];

    return Container(
      width: expanded ? UiV2Metrics.sidebarWidth : UiV2Metrics.railWidth,
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(right: BorderSide(color: t.line)),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: UiV2Spacing.s3,
            vertical: UiV2Spacing.s5,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 品牌行
              Row(
                mainAxisAlignment:
                    expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  // 品牌行：标记与 App 图标（resonance_app/assets/icon/app_icon.svg）同一份几何。
                  // 这里原来是「音符图标 + 圆角方块」临时拼的，与 App 图标不是同一套图形，
                  // 换了图标就对不上（用户就是看到侧栏还是旧音符才发现的）。
                  // 颜色仍跟随主题（accent / accentInk），不写死品牌色。
                  UiV2BrandRow(showName: expanded),
                  if (expanded) ...[
                    if (showBack) ...[
                      // 返回键靠右：与品牌字标拉开距离，
                      // 位置也固定下来（原来紧贴字标，字标长度一变它就左右漂）
                      const Spacer(),
                      // 描边圆角方形：与侧栏底部「切换到深色」那个 ghost 按钮同款，
                      // 让返回键从"孤立箭头"变成一个明确的控件
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: t.line),
                          borderRadius: UiV2Radii.brMd,
                        ),
                        child: UiV2IconButton(
                          icon: UiV2Icons.arrowLeft,
                          semanticLabel: '返回',
                          size: 36,
                          // 与外面那圈描边同为方圆角，hover 才不会变成圆形
                          radius: UiV2Radii.brMd,
                          onTap: () => ref.read(navProvider.notifier).back(),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
              const SizedBox(height: UiV2Spacing.s5),
              // 主导航
              for (final dest in kSidebarDestinations) ...[
                const SizedBox(height: 2),
                _SidebarItem(
                  key: ValueKey('nav_${dest.route}'),
                  destination: dest,
                  selected: active == dest.route,
                  expanded: expanded,
                  onTap: () => ref.read(navProvider.notifier).go(dest.route),
                ),
              ],
              if (expanded) ...[
                const SizedBox(height: UiV2Spacing.s5),
                // 「你的歌单」
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: UiV2Spacing.s3),
                  child: Text(
                    '你的歌单',
                    style: UiV2Text.capsLabel.copyWith(color: t.textMute),
                  ),
                ),
                const SizedBox(height: UiV2Spacing.s2),
                for (final playlist in playlists.take(8))
                  UiV2Pressable(
                    onTap: () =>
                        ref.read(navProvider.notifier).go('playlist', playlist.id),
                    radius: UiV2Radii.brSm,
                    hoverColor: t.surface2,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 40),
                      padding: const EdgeInsets.symmetric(
                        horizontal: UiV2Spacing.s3,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: t.accentSoft,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(width: UiV2Spacing.s3),
                          Expanded(
                            child: Text(
                              playlist.name,
                              style: UiV2Text.rowLabel.copyWith(
                                color: t.textDim,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: UiV2Spacing.s5),
                // 主题切换（.ghost-btn）
                UiV2Pressable(
                  onTap: () => ref.read(themeModeProvider.notifier).toggleDark(),
                  radius: UiV2Radii.brMd,
                  hoverColor: t.surface2,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: UiV2Spacing.s3,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: t.line),
                      borderRadius: UiV2Radii.brMd,
                    ),
                    child: Row(
                      children: [
                        UiV2Icon(
                          ref.watch(themeModeProvider) == ThemeMode.dark
                              ? UiV2Icons.sun
                              : UiV2Icons.moon,
                          size: 22,
                          color: t.textDim,
                        ),
                        const SizedBox(width: UiV2Spacing.s3),
                        Expanded(
                          child: Text(
                            ref.watch(themeModeProvider) == ThemeMode.dark
                                ? '切换到浅色'
                                : '切换到深色',
                            style: UiV2Text.rowLabel.copyWith(color: t.textDim),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: UiV2Spacing.s5),
                Center(
                  child: UiV2IconButton(
                    icon: ref.watch(themeModeProvider) == ThemeMode.dark
                        ? UiV2Icons.sun
                        : UiV2Icons.moon,
                    semanticLabel: '切换深浅色主题',
                    onTap: () => ref.read(themeModeProvider.notifier).toggleDark(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 侧栏导航项（.nav__item）
class _SidebarItem extends StatelessWidget {
  final NavDestination destination;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  const _SidebarItem({
    super.key,
    required this.destination,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final fg = selected ? t.accent : t.textDim;
    return Semantics(
      label: destination.label,
      selected: selected,
      button: true,
      child: UiV2Pressable(
        onTap: onTap,
        radius: UiV2Radii.brMd,
        hoverColor: t.surface2,
        child: AnimatedContainer(
          duration: UiV2Motion.d1,
          curve: UiV2Motion.enter,
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? UiV2Spacing.s3 : 0,
          ),
          decoration: BoxDecoration(
            color: selected ? t.accentSoft : const Color(0x00000000),
            borderRadius: UiV2Radii.brMd,
          ),
          child: Row(
            mainAxisAlignment:
                expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              UiV2Icon(destination.icon, size: 21, color: fg),
              if (expanded) ...[
                const SizedBox(width: UiV2Spacing.s3),
                Expanded(
                  child: Text(
                    destination.label,
                    style: UiV2Text.rowLabel.copyWith(color: fg),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部导航（.tabbar）—— 仅移动端显示；二级页收起
class UiV2TabBar extends ConsumerWidget {
  /// 构造底部导航
  const UiV2TabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final nav = ref.watch(navProvider);
    final active = kNavFor[nav.current.name] ?? nav.current.name;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: EdgeInsets.fromLTRB(6, 4, 6, 4 + bottomInset),
          decoration: BoxDecoration(
            color: t.surface.withValues(alpha: 0.92),
            border: Border(top: BorderSide(color: t.line)),
          ),
          child: Row(
            children: [
              for (final dest in kTabDestinations)
                Expanded(
                  child: _Tab(
                    destination: dest,
                    selected: active == dest.route,
                    onTap: () => ref.read(navProvider.notifier).go(dest.route),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部 Tab（.tab）
class _Tab extends StatelessWidget {
  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  const _Tab({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final fg = selected ? t.accent : t.textMute;
    return Semantics(
      label: destination.label,
      selected: selected,
      button: true,
      child: UiV2Pressable(
        onTap: onTap,
        radius: UiV2Radii.brMd,
        child: AnimatedContainer(
          duration: UiV2Motion.d1,
          curve: UiV2Motion.enter,
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(
            color: selected ? t.accentSoft : const Color(0x00000000),
            borderRadius: UiV2Radii.brMd,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              UiV2Icon(destination.icon, size: 22, color: fg),
              const SizedBox(height: 3),
              Text(destination.label, style: UiV2Text.tabLabel.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
