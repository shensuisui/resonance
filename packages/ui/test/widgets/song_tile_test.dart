/// SongTile Widget 测试
///
/// 对应 lib/src/widgets/song_tile.dart。
/// SongTile 为 ConsumerWidget，依赖全局播放状态 provider：
/// - currentSongProvider / isPlayingProvider → 当前播放歌曲显示黑罩+跳动动画
/// - playbackLoadingProvider → 当前歌曲请求播放 URL 时显示白圈
/// 测试用 ProviderContainer 注入状态。
///
/// 验证：
/// - 标题/歌手/来源标签渲染（来源标签格式「 · sourceId」）
/// - onTap 点击回调
/// - onArtistTap 提供/未提供时歌手名的点击行为
/// - 无封面时显示默认音符图标
/// - 封面网络加载失败时回退默认封面（测试环境网络被拦截 → errorBuilder）
/// - trailing 自定义尾部组件渲染
/// - 播放中：封面黑罩 + 跳动动画；loading：黑罩 + 白圈
/// - 非当前歌曲无覆盖层
///
/// 模拟数据来源：内联构造的 Song（sourceId 固定 test_src）+ ProviderContainer。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:ui/ui.dart';

void main() {
  /// 用 MaterialApp + ProviderScope 包裹被测 Widget（SongTile 依赖 Theme + provider）
  Widget wrap(Widget child) => ProviderScope(
        child: MaterialApp(home: Scaffold(body: child)),
      );

  /// 标准测试歌曲（无封面，避免默认触发网络图片加载）
  final song = Song(
    id: '1', sourceId: 'test_src', title: '晴天', artist: '周杰伦',
  );

  /// 用自定义容器注入播放状态后泵入 SongTile
  Future<ProviderContainer> pumpWithState(
    WidgetTester tester, {
    Song? currentSong,
    bool isPlaying = false,
    String? loadingKey,
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    if (currentSong != null) {
      container.read(currentSongProvider.notifier).setSong(currentSong);
    }
    container.read(isPlayingProvider.notifier).setPlaying(isPlaying);
    if (loadingKey != null) {
      container.read(playbackLoadingProvider.notifier).setLoading(loadingKey);
    }
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: SongTile(song: song))),
    ));
    return container;
  }

  group('SongTile 渲染', () {
    testWidgets('显示标题、歌手和来源标签', (tester) async {
      await tester.pumpWidget(wrap(SongTile(song: song)));

      expect(find.text('晴天'), findsOneWidget);
      expect(find.text('周杰伦'), findsOneWidget);
      // 来源标签格式：「 · sourceId」（见 _buildSubtitle）
      expect(find.text(' · test_src'), findsOneWidget);
    });

    testWidgets('无封面时显示默认音符图标', (tester) async {
      await tester.pumpWidget(wrap(SongTile(song: song)));

      expect(find.byIcon(Icons.music_note), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('封面加载失败时回退默认封面', (tester) async {
      // flutter_test 环境拦截所有网络请求（返回 400），
      // Image.network 触发 errorBuilder → 应显示默认音符封面
      final withCover = song.copyWith(coverUrl: 'https://example.com/c.jpg');
      await tester.pumpWidget(wrap(SongTile(song: withCover)));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.music_note), findsOneWidget);
    });

    testWidgets('trailing 组件原样渲染', (tester) async {
      await tester.pumpWidget(wrap(SongTile(
        song: song,
        trailing: const Icon(Icons.more_vert, key: Key('tile_trailing')),
      )));

      expect(find.byKey(const Key('tile_trailing')), findsOneWidget);
    });
  });

  group('SongTile 播放状态覆盖层', () {
    testWidgets('非当前歌曲无覆盖层', (tester) async {
      await pumpWithState(tester,
          currentSong: song.copyWith(id: 'other'),
          isPlaying: true);
      await tester.pump();

      // 覆盖层 Stack 带专属 Key，避免命中 ListTile 内部 Stack
      expect(find.byKey(const Key('song_tile_playing_overlay')), findsNothing);
    });

    testWidgets('当前歌曲播放中：黑罩 + 跳动动画', (tester) async {
      await pumpWithState(tester, currentSong: song, isPlaying: true);
      await tester.pump();
      // 让动画跑一帧（repeat 动画 pump 一帧可见）
      await tester.pump(const Duration(milliseconds: 100));

      // 覆盖层出现（封面 + 黑罩 + 动画三层）
      final stack = tester.widget<Stack>(
          find.byKey(const Key('song_tile_playing_overlay')));
      expect(stack.children.length, greaterThanOrEqualTo(2));
      // loading 圈圈不应出现（播放中用跳动条）
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // 跳动动画容器（白色竖条）存在
      expect(
        find.byWidgetPredicate((w) =>
            w is Container && w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == Colors.white),
        findsWidgets,
      );
    });

    testWidgets('当前歌曲 loading：黑罩 + 白色圈圈', (tester) async {
      await pumpWithState(tester,
          currentSong: song, loadingKey: song.globalKey);
      await tester.pump();

      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.color, Colors.white);
      // 覆盖层存在
      expect(find.byKey(const Key('song_tile_playing_overlay')),
          findsOneWidget);
    });

    testWidgets('其他歌曲 loading 不影响本项', (tester) async {
      await pumpWithState(tester,
          currentSong: song, loadingKey: 'other_src:99');
      await tester.pump();

      expect(find.byKey(const Key('song_tile_playing_overlay')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('SongTile 交互', () {
    testWidgets('点击整行触发 onTap', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(wrap(SongTile(
        song: song,
        onTap: () => tapped++,
      )));

      await tester.tap(find.byType(ListTile));
      expect(tapped, 1);
    });

    testWidgets('提供 onArtistTap 时点击歌手名回调歌手名', (tester) async {
      String? tappedArtist;
      await tester.pumpWidget(wrap(SongTile(
        song: song,
        onArtistTap: (name) => tappedArtist = name,
      )));

      await tester.tap(find.text('周杰伦'));
      expect(tappedArtist, '周杰伦');
    });

    testWidgets('未提供 onArtistTap 时点击歌手名无回调且不报错', (tester) async {
      // 边界：GestureDetector.onTap 为 null 时点击应为无操作
      await tester.pumpWidget(wrap(SongTile(song: song)));

      await tester.tap(find.text('周杰伦'));
      await tester.pump();
      // 无异常即通过；再验证整行 onTap 也未配置时无副作用
      expect(tester.takeException(), isNull);
    });

    testWidgets('onArtistTap 与 onTap 互不干扰', (tester) async {
      // 点击歌手名只触发 onArtistTap，不触发整行 onTap
      var rowTapped = 0;
      String? tappedArtist;
      await tester.pumpWidget(wrap(SongTile(
        song: song,
        onTap: () => rowTapped++,
        onArtistTap: (name) => tappedArtist = name,
      )));

      await tester.tap(find.text('周杰伦'));
      expect(tappedArtist, '周杰伦');
      expect(rowTapped, 0, reason: '歌手名手势应拦截整行点击');

      // 点击标题区域仍触发整行 onTap
      await tester.tap(find.text('晴天'));
      expect(rowTapped, 1);
    });
  });
}