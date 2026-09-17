/// LyricsView 歌词视图测试
///
/// 验证：
/// 1. 无歌词时显示空态
/// 2. 有歌词渲染行；无封面时无模糊背景且不崩
/// 3. 当前行字号大于非当前行（高亮）
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:ui/ui.dart';

/// 固定歌词 Notifier（不依赖源管理器）
class _FixedLyricsNotifier extends LyricsNotifier {
  final Lyrics? _lyrics;

  _FixedLyricsNotifier(this._lyrics);

  @override
  Lyrics? build() => _lyrics;
}

void main() {
  const lines = [
    LyricLine(time: Duration(seconds: 0), text: '第一行歌词'),
    LyricLine(time: Duration(seconds: 4), text: '第二行歌词'),
    LyricLine(time: Duration(seconds: 8), text: '第三行歌词'),
  ];
  const lyrics =
      Lyrics(songId: '1', sourceId: 'netease', lines: lines);

  Future<ProviderContainer> pumpLyrics(
    WidgetTester tester, {
    Lyrics? value = lyrics,
    Duration position = Duration.zero,
    Song? song,
  }) async {
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWith((ref) => InMemoryDatabaseProvider()),
      lyricsProvider.overrideWith(() => _FixedLyricsNotifier(value)),
    ]);
    addTearDown(container.dispose);
    container
        .read(playbackPositionProvider.notifier)
        .setPosition(position);
    if (song != null) {
      container.read(currentSongProvider.notifier).setSong(song);
    }
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: LyricsView())),
    ));
    return container;
  }

  testWidgets('无歌词显示空态', (tester) async {
    await pumpLyrics(tester, value: null);
    expect(find.text('暂无歌词'), findsOneWidget);
  });

  testWidgets('有歌词渲染行，无封面时无模糊背景且不崩', (tester) async {
    await pumpLyrics(tester, position: const Duration(seconds: 5));
    expect(find.text('第一行歌词'), findsOneWidget);
    expect(find.text('第二行歌词'), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('有封面时渲染模糊背景', (tester) async {
    await pumpLyrics(
      tester,
      position: const Duration(seconds: 5),
      song: Song(
        id: '1',
        sourceId: 'netease',
        title: '晴天',
        artist: '周杰伦',
        coverUrl: 'https://invalid.example/cover.jpg',
      ),
    );
    // ImageFiltered 存在（封面加载失败时 errorBuilder 置空但结构保留）
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('当前行字号大于非当前行', (tester) async {
    await pumpLyrics(tester, position: const Duration(seconds: 2));
    // 当前行（第一行，time 0 <= 2s）字号放大：全部行中应同时存在
    // 放大字号（18）与常规字号（14）
    final sizes = tester
        .widgetList<AnimatedDefaultTextStyle>(find.byType(AnimatedDefaultTextStyle))
        .map((s) => s.style.fontSize)
        .toList();
    expect(sizes, contains(18), reason: '当前行应放大到 18');
    expect(
      sizes.where((s) => s == 14).length,
      greaterThanOrEqualTo(2),
      reason: '非当前行应保持 14',
    );
  });
}
