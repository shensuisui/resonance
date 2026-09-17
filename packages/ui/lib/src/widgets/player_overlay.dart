/// 播放器覆盖层（阶段二 M2：迷你条 ↔ 全屏播放器的拖动切换）
///
/// 结构：Stack 顶层渲染两个部分——
/// 1. 全屏播放器面板：value 0（屏幕外）↔ 1（全屏）随拖动/动画切换，
///    展开时覆盖主界面（含底部导航）；面板内可下拉收起。
/// 2. 迷你条：主界面底部（导航上方），上滑展开，点击展开。
///
/// 手势模型：AnimationController.value 0~1 表示展开进度，拖动直接改值
/// （跟手），松手按进度 settle（>0.5 展开，否则收起）；状态同步到
/// PlayerOverlayNotifier（M1）。
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../pages/player_page.dart';
import 'mini_player.dart';

class PlayerOverlay extends ConsumerStatefulWidget {
  /// 迷你条距屏幕底部偏移（竖屏 = 底部导航高度，横屏 = 0）
  final double miniBarBottom;

  const PlayerOverlay({super.key, this.miniBarBottom = 0});

  @override
  ConsumerState<PlayerOverlay> createState() => _PlayerOverlayState();
}

class _PlayerOverlayState extends ConsumerState<PlayerOverlay>
    with SingleTickerProviderStateMixin {
  /// 展开进度：0 = 迷你条，1 = 全屏
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 拖动跟手：上滑（deltaDy 负）→ value 增大（展开）
  void _drag(double deltaDy, double screenH) {
    _controller.value =
        (_controller.value - deltaDy / screenH).clamp(0.0, 1.0);
  }

  /// 松手：按进度决定展开/收起，同步状态机
  void _dragEnd() {
    final target = _controller.value > 0.5 ? 1.0 : 0.0;
    final notifier = ref.read(playerOverlayProvider.notifier);
    if (target > 0.5) {
      notifier.expand();
    } else {
      notifier.collapse();
    }
    _controller.animateTo(target, curve: Curves.easeOutCubic);
  }

  /// 迷你条点击展开
  void _expand() {
    ref.read(playerOverlayProvider.notifier).expand();
    _controller.animateTo(1, curve: Curves.easeOutCubic);
  }

  /// 全屏面板收起（下拉箭头 / 下拉手势）
  void _collapse() {
    ref.read(playerOverlayProvider.notifier).collapse();
    _controller.animateTo(0, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();

    final overlay = ref.watch(playerOverlayProvider);
    final screenH = MediaQuery.sizeOf(context).height;
    // 迷你条自身高度（近似，用于上滑时下移淡出）
    const miniH = 72.0;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final value = _controller.value;
        final showingPanel = value > 0.001;
        final showMiniBar =
            overlay != PlayerOverlayState.expanded || value < 0.999;

        return Stack(
          children: [
            // 全屏播放器面板（value=0 时屏外不可见，且不拦截手势）
            Positioned.fill(
              child: showingPanel
                  ? GestureDetector(
                      onVerticalDragUpdate: (d) => _drag(d.delta.dy, screenH),
                      onVerticalDragEnd: (_) => _dragEnd(),
                      child: Transform.translate(
                        offset: Offset(0, (1 - value) * screenH),
                        child: PlayerPage(
                          embedded: true,
                          onCollapse: _collapse,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            // 迷你条：随展开淡出并下移
            if (showMiniBar)
              Positioned(
                left: 0,
                right: 0,
                bottom: widget.miniBarBottom + (1 - value) * miniH,
                child: Opacity(
                  opacity: (1 - value).clamp(0.0, 1.0),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (d) => _drag(d.delta.dy, screenH),
                    onVerticalDragEnd: (_) => _dragEnd(),
                    onTap: _expand,
                    child: MiniPlayer(onTap: _expand),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
