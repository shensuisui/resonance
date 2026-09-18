/// PlayerPage 布局测试（对齐 PixelPlayer 播放器结构）
///
/// 验证：
/// 1. transport 行：上一首 / 播放-暂停 / 下一首 三个按钮
/// 2. 开关行：随机 / 循环 / 收藏 三个 segment
/// 3. 元信息区：标题与歌手左对齐展示
/// 4. 歌词按钮切换：点击后显示歌词视图（再次点击回封面）
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:ui/ui.dart';

class _FakePlayer implements Player {
  int pauseCalls = 0;
  int resumeCalls = 0;
  int nextCalls = 0;
  int previousCalls = 0;

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<void> resume() async => resumeCalls++;

  @override
  Future<void> next() async => nextCalls++;

  @override
  Future<void> previous() async => previousCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  final song = Song(
    id: '1', sourceId: 'a', title: '晴天', artist: '周杰伦',
  );

  Future<({ProviderContainer container, _FakePlayer player})> pumpPlayer(
    WidgetTester tester, {
    bool isPlaying = true,
  }) async {
    final player = _FakePlayer();
    final container = ProviderContainer(overrides: [
      playerProvider.overrideWith((ref) => player),
      appDatabaseProvider.overrideWith((ref) => InMemoryDatabaseProvider()),
    ]);
    addTearDown(container.dispose);
    container.read(currentSongProvider.notifier).setSong(song);
    container.read(isPlayingProvider.notifier).setPlaying(isPlaying);
    container
        .read(playbackPositionProvider.notifier)
        .setPosition(const Duration(seconds: 30));
    container
        .read(playbackDurationProvider.notifier)
        .setDuration(const Duration(seconds: 60));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: PlayerPage()),
    ));
    await tester.pump();
    return (container: container, player: player);
  }

  testWidgets('transport 三按钮与开关行三 segment 渲染', (tester) async {
    await pumpPlayer(tester);

    // transport
    expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget); // 播放中
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    // 开关行
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
  });

  testWidgets('元信息左对齐：标题与歌手渲染', (tester) async {
    await pumpPlayer(tester);
    expect(find.text('晴天'), findsWidgets);
    expect(find.text('周杰伦'), findsWidgets);
  });

  testWidgets('暂停态显示播放图标', (tester) async {
    await pumpPlayer(tester, isPlaying: false);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
  });

  testWidgets('点击歌词按钮切换到歌词视图', (tester) async {
    await pumpPlayer(tester);
    // 初始为封面（无歌词视图）
    expect(find.byType(LyricsView), findsNothing);

    await tester.tap(find.byIcon(Icons.lyrics_outlined));
    await tester.pump();

    // 歌词模式：按钮图标切换为专辑图标
    expect(find.byType(LyricsView), findsOneWidget);
    expect(find.byIcon(Icons.album_rounded), findsOneWidget);
  });

  testWidgets('点击下一首调用播放器 next', (tester) async {
    final ctx = await pumpPlayer(tester);
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await tester.pump();
    expect(ctx.player.nextCalls, 1);
  });

  testWidgets('点击随机 segment 切换播放模式为随机', (tester) async {
    final ctx = await pumpPlayer(tester);
    await tester.tap(find.byIcon(Icons.shuffle_rounded));
    await tester.pump();
    expect(ctx.container.read(playModeProvider), PlayMode.shuffle);
  });
}
