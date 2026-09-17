/// PlayerOverlay 播放器覆盖层 Widget 测试（阶段二 M2）
///
/// 对应 lib/src/widgets/player_overlay.dart。
/// 通过 ProviderContainer.overrides 注入状态与假播放器，验证：
/// - 无当前歌曲时渲染为空（不显示迷你条/面板）
/// - 有歌曲时渲染迷你条；点击展开全屏 PlayerPage
/// - 迷你条上滑拖动展开全屏；展开态下拉收起
///
/// 模拟数据来源：内联 Song + Riverpod Notifier 注入；
/// 播放器 _FakePlayer（noSuchMethod 转发）；DAO 用 core 的 InMemoryDatabaseProvider。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:ui/ui.dart';

class _FakePlayer implements Player {
  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  final song = Song(
    id: '1', sourceId: 'test_src', title: '晴天', artist: '周杰伦',
  );

  Future<ProviderContainer> pumpOverlay(
    WidgetTester tester, {
    Song? currentSong,
  }) async {
    final container = ProviderContainer(overrides: [
      playerProvider.overrideWith((ref) => _FakePlayer()),
      appDatabaseProvider.overrideWith((ref) => InMemoryDatabaseProvider()),
    ]);
    addTearDown(container.dispose);

    if (currentSong != null) {
      container.read(currentSongProvider.notifier).setSong(currentSong);
      container.read(isPlayingProvider.notifier).setPlaying(false);
      container
          .read(playbackPositionProvider.notifier)
          .setPosition(Duration.zero);
      container
          .read(playbackDurationProvider.notifier)
          .setDuration(Duration.zero);
    }

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: PlayerOverlay())),
    ));
    return container;
  }

  testWidgets('无当前歌曲时渲染空组件', (tester) async {
    await pumpOverlay(tester);
    expect(find.byType(MiniPlayer), findsNothing);
    expect(find.byType(PlayerPage), findsNothing);
  });

  testWidgets('有歌曲渲染迷你条，点击展开全屏播放器', (tester) async {
    await pumpOverlay(tester, currentSong: song);
    expect(find.byType(MiniPlayer), findsOneWidget);
    // 展开前全屏面板在屏幕外（PlayerPage 不参与命中/不可见）
    expect(find.byType(PlayerPage), findsNothing);

    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsOneWidget);
    // 覆盖层状态机同步为 expanded
    expect(
      tester.element(find.byType(PlayerPage)),
      isNotNull,
    );
  });

  testWidgets('迷你条上滑拖动展开，展开态下拉收起', (tester) async {
    await pumpOverlay(tester, currentSong: song);
    expect(find.byType(PlayerPage), findsNothing);

    // 上滑超过半屏 → 展开
    await tester.fling(
      find.byType(MiniPlayer),
      const Offset(0, -500),
      1200,
    );
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsOneWidget);

    // 全屏态下拉超过半屏 → 收起
    await tester.fling(
      find.byType(PlayerPage),
      const Offset(0, 500),
      1200,
    );
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);
    expect(find.byType(MiniPlayer), findsOneWidget);
  });

  testWidgets('迷你条状态与状态机同步', (tester) async {
    final container = await pumpOverlay(tester, currentSong: song);
    expect(
      container.read(playerOverlayProvider),
      PlayerOverlayState.mini,
    );
    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();
    expect(
      container.read(playerOverlayProvider),
      PlayerOverlayState.expanded,
    );
  });
}
