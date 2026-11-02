/// 「我喜欢的音乐」详情头部与固定封面的回归测试
///
/// 两件事钉住：
///   ① 手机（< 768）改用与歌单详情同款的紧凑头部 —— 封面与文字左右并排，
///      不再在封面下面再堆「标题 + 统计 + 按钮」那一整段；
///   ② 封面固定是 [LikedHeartArt]（不透明浅粉底 + 实心红心），宽屏 hero 同样用它。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:uiv2/src/components/hero.dart';
import 'package:uiv2/src/design/icons.dart';
import 'package:uiv2/src/design/theme.dart';
import 'package:uiv2/src/pages/liked_page.dart';
import 'package:uiv2/src/providers/providers.dart';

/// 造几首收藏曲（不需要真实 DAO：直接覆盖 likedSongsProvider）
List<Song> _songs(int n) => [
  for (var i = 0; i < n; i++)
    Song(
      id: 's$i',
      sourceId: 'demo',
      title: '歌曲 $i',
      artist: '歌手 $i',
      duration: 200 + i,
    ),
];

void main() {
  /// 在指定逻辑宽度渲染页面
  Future<void> pumpAt(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = InMemoryDatabaseProvider();
    await db.initialize();
    final container = ProviderContainer(overrides: <Override>[
      likedSongsProvider.overrideWithValue(_songs(4)),
      appDatabaseProvider.overrideWithValue(db),
      sourceManagerProvider.overrideWithValue(SourceManager()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: UiV2DesignTheme.light(),
        builder: (context, child) =>
            child == null ? const SizedBox() : UiV2Scope(child: child),
        home: const Scaffold(body: LikedPage()),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('手机 444：走紧凑头部（无大 hero），封面固定心形', (tester) async {
    await pumpAt(tester, 444);
    expect(find.byType(LikedHeartArt), findsOneWidget, reason: '封面应是固定心形');
    expect(find.byType(UiV2Hero), findsNothing,
        reason: '手机端不该再用「封面在上、标题统计按钮在下」的大 hero');
    expect(find.text('收藏'), findsOneWidget);
    expect(find.byKey(const ValueKey('liked_play_all')), findsOneWidget);
    expect(find.byKey(const ValueKey('liked_shuffle')), findsOneWidget);
  });

  testWidgets('手机 444：头部明显变矮（封面顶到第一个排序 chip 不超过 260）', (tester) async {
    await pumpAt(tester, 444);
    final coverTop = tester.getTopLeft(find.byType(LikedHeartArt)).dy;
    final chipTop = tester.getTopLeft(find.text('最近喜欢')).dy;
    // 封面本身 220 + 上边距 s2 + 底部 s3 ≈ 248；给一点余量卡在 260
    expect(chipTop - coverTop, lessThan(260),
        reason: '头部高度应只由封面决定，不再叠加标题/统计/按钮那一段');
  });

  testWidgets('宽屏 1200：走 hero，但封面同样是固定心形', (tester) async {
    await pumpAt(tester, 1200);
    expect(find.byType(UiV2Hero), findsOneWidget);
    expect(find.byType(LikedHeartArt), findsOneWidget);
  });

  testWidgets('LikedHeartArt：底色不透明，画的是实心红心', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: UiV2DesignTheme.light(),
      builder: (context, child) =>
          child == null ? const SizedBox() : UiV2Scope(child: child),
      home: const Scaffold(body: SizedBox(height: 200, width: 200, child: LikedHeartArt())),
    ));
    final box = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(LikedHeartArt),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(box.color.a, 1.0, reason: '底色必须不透明，否则会透出父级');
    final icon = tester.widget<UiV2Icon>(find.byType(UiV2Icon).first);
    expect(icon.name, UiV2Icons.heartFill, reason: '用实心红心，不用描边心');
  });
}
