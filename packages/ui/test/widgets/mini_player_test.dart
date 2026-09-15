/// MiniPlayer Widget 测试
///
/// 对应 lib/src/widgets/mini_player.dart。
/// 通过 ProviderContainer.overrides 注入状态与假播放器，验证：
/// - 无当前歌曲时渲染为空（SizedBox.shrink，零尺寸）
/// - 显示「标题 - 歌手」与进度条（progress = position/duration）
/// - duration 为 0 时进度取 0（除零边界）
/// - isPlaying 切换播放/暂停图标
/// - 点击播放/暂停按钮调用 player.resume()/pause()
/// - 点击整条导航到全屏 PlayerPage
///
/// 模拟数据来源：
/// - 歌曲/播放状态：内联 Song + Riverpod Notifier 直接注入
/// - 播放器：_FakePlayer（记录 pause/resume 调用次数，其余成员
///   经 noSuchMethod 转发——MiniPlayer 只用到 pause/resume）
/// - PlayerPage 依赖的 DAO：core 的 InMemoryDatabaseProvider（纯内存）
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:ui/ui.dart';

/// 假播放器：只实现 MiniPlayer 用到的 pause/resume 并计数，
/// 其余 Player 成员统一经 noSuchMethod 转发（返回 null，测试不会触达）
class _FakePlayer implements Player {
  int pauseCalls = 0;
  int resumeCalls = 0;

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<void> resume() async => resumeCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  final song = Song(
    id: '1', sourceId: 'test_src', title: '晴天', artist: '周杰伦',
  );

  /// 泵入带状态注入的 MiniPlayer，返回容器与假播放器供断言
  ///
  /// 注意：pumpWidget 是受守卫的异步 API，helper 必须 async + await，
  /// 否则后续 pump/tap 触发 Guarded function conflict。
  Future<({ProviderContainer container, _FakePlayer player})> pumpMiniPlayer(
    WidgetTester tester, {
    Song? currentSong,
    bool isPlaying = false,
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
  }) async {
    final player = _FakePlayer();
    final container = ProviderContainer(overrides: [
      playerProvider.overrideWith((ref) => player),
      // PlayerPage（导航目标）依赖 settingsDao/favoritesDao → 内存实现
      appDatabaseProvider.overrideWith((ref) => InMemoryDatabaseProvider()),
    ]);
    addTearDown(container.dispose);

    // pump 前注入状态，首帧即渲染目标状态，无需二次 pump
    if (currentSong != null) {
      container.read(currentSongProvider.notifier).setSong(currentSong);
      container.read(isPlayingProvider.notifier).setPlaying(isPlaying);
      container
          .read(playbackPositionProvider.notifier)
          .setPosition(position);
      container
          .read(playbackDurationProvider.notifier)
          .setDuration(duration);
    }

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: MiniPlayer())),
    ));
    return (container: container, player: player);
  }

  group('MiniPlayer 渲染', () {
    testWidgets('无当前歌曲时渲染为零尺寸空组件', (tester) async {
      await pumpMiniPlayer(tester);

      // currentSong == null → SizedBox.shrink：无进度条、无按钮、零尺寸
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(IconButton), findsNothing);
      expect(tester.getSize(find.byType(MiniPlayer)), Size.zero);
    });

    testWidgets('显示「标题 - 歌手」文本', (tester) async {
      await pumpMiniPlayer(tester, currentSong: song);

      expect(find.text('晴天 - 周杰伦'), findsOneWidget);
    });

    testWidgets('进度条按 position/duration 计算', (tester) async {
      await pumpMiniPlayer(
        tester,
        currentSong: song,
        position: const Duration(seconds: 30),
        duration: const Duration(seconds: 60),
      );

      final indicator = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(indicator.value, 0.5);
    });

    testWidgets('duration 为 0 时进度取 0（除零边界）', (tester) async {
      await pumpMiniPlayer(tester, currentSong: song);

      final indicator = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(indicator.value, 0.0);
      expect(tester.takeException(), isNull);
    });
  });

  group('MiniPlayer 播放/暂停', () {
    testWidgets('播放中显示暂停图标', (tester) async {
      await pumpMiniPlayer(tester, currentSong: song, isPlaying: true);

      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    });

    testWidgets('未播放显示播放图标', (tester) async {
      await pumpMiniPlayer(tester, currentSong: song, isPlaying: false);

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsNothing);
    });

    testWidgets('未播放时点击按钮调用 resume', (tester) async {
      final r =
          await pumpMiniPlayer(tester, currentSong: song, isPlaying: false);

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      expect(r.player.resumeCalls, 1);
      expect(r.player.pauseCalls, 0);
    });

    testWidgets('播放中点击按钮调用 pause', (tester) async {
      final r =
          await pumpMiniPlayer(tester, currentSong: song, isPlaying: true);

      await tester.tap(find.byIcon(Icons.pause_rounded));
      expect(r.player.pauseCalls, 1);
      expect(r.player.resumeCalls, 0);
    });
  });

  group('MiniPlayer 导航', () {
    testWidgets('点击整条导航到全屏 PlayerPage', (tester) async {
      // PlayerPage 封面区固定 280px 高 + 标题/歌手，在默认 800x600
      // 测试画布会溢出（真实手机屏幕更窄长），这里用 800x1600 逻辑像素
      // 模拟手机视口
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpMiniPlayer(tester, currentSong: song);

      // 点击标题区域（位于 InkWell 内）
      await tester.tap(find.text('晴天 - 周杰伦'));
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsOneWidget);
      // PlayerPage 复用同一容器状态：AppBar 标题为当前歌曲名
      expect(find.text('晴天'), findsWidgets);
    });
  });
}
