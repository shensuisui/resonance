/// SongTile Widget 测试
///
/// 对应 lib/src/widgets/song_tile.dart。
/// 验证：
/// - 标题/歌手/来源标签渲染（来源标签格式「 · sourceId」）
/// - onTap 点击回调
/// - onArtistTap 提供/未提供时歌手名的点击行为
/// - 无封面时显示默认音符图标
/// - 封面网络加载失败时回退默认封面（测试环境网络被拦截 → errorBuilder）
/// - trailing 自定义尾部组件渲染
///
/// 模拟数据来源：内联构造的 Song（sourceId 固定 test_src），
/// 不依赖 provider / 网络 / 文件系统。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:ui/ui.dart';

void main() {
  /// 用 MaterialApp 包裹被测 Widget（SongTile 依赖 Theme）
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: child));

  /// 标准测试歌曲（无封面，避免默认触发网络图片加载）
  final song = Song(
    id: '1', sourceId: 'test_src', title: '晴天', artist: '周杰伦',
  );

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
