/// PlayerOverlayNotifier 播放器覆盖层状态机测试（阶段二 M1）
///
/// 验证：
/// 1. 初始状态为 mini
/// 2. expand / collapse / hide 状态迁移且清零拖动偏移
/// 3. setDragOffset 更新偏移并触发重建
/// 4. settle 按阈值决定展开/收起（上拉超过 kPlayerOverlayExpandThreshold → 展开）
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

void main() {
  test('初始状态为 mini', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(playerOverlayProvider), PlayerOverlayState.mini);
    expect(container.read(playerOverlayProvider.notifier).dragOffset, 0);
  });

  test('expand 迁移到 expanded 且清零偏移', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(playerOverlayProvider.notifier);
    notifier.setDragOffset(-80);
    notifier.expand();
    expect(container.read(playerOverlayProvider), PlayerOverlayState.expanded);
    expect(notifier.dragOffset, 0);
  });

  test('collapse 从 expanded 回 mini', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(playerOverlayProvider.notifier);
    notifier.expand();
    notifier.collapse();
    expect(container.read(playerOverlayProvider), PlayerOverlayState.mini);
  });

  test('hide 迁移到 hidden', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(playerOverlayProvider.notifier);
    notifier.hide();
    expect(container.read(playerOverlayProvider), PlayerOverlayState.hidden);
  });

  test('setDragOffset 更新偏移且触发重建', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(playerOverlayProvider.notifier);
    notifier.setDragOffset(-150);
    expect(notifier.dragOffset, -150);
    // 重建后仍保持（watch 依赖已通知）
    container.read(playerOverlayProvider);
    expect(notifier.dragOffset, -150);
  });

  test('settle 上拉超过阈值展开，不足收起', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(playerOverlayProvider.notifier);

    // 上拉 150px（超过阈值 120）→ 展开
    notifier.setDragOffset(-150);
    notifier.settle();
    expect(container.read(playerOverlayProvider), PlayerOverlayState.expanded);

    // 重新收起后仅上拉 50px → 保持 mini
    notifier.collapse();
    notifier.setDragOffset(-50);
    notifier.settle();
    expect(container.read(playerOverlayProvider), PlayerOverlayState.mini);

    // 下拉（正偏移）→ 收起
    notifier.setDragOffset(60);
    notifier.settle();
    expect(container.read(playerOverlayProvider), PlayerOverlayState.mini);
  });
}
