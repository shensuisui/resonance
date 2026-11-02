/// 详情页操作栏与手机端头部的组件测试
///
/// 排布照参考页（漫画详情页）：操作栏**通栏 + 各项等分 + 图标在上文字在下**，
/// 且颜色一律次级灰（不做主色高亮）。头部则是封面与文字左右并排，
/// 文字块相对封面**垂直居中**（贴顶会让右侧几行挤在顶上）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/components/hero.dart';
import 'package:uiv2/src/design/icons.dart';
import 'package:uiv2/src/design/theme.dart';
import 'package:uiv2/src/design/tokens.dart';

/// 空回调（只关心排布时用）
void _noop() {}

/// 包一层主题作用域
Widget _wrap(Widget child) => MaterialApp(
      theme: UiV2DesignTheme.light(),
      builder: (context, c) =>
          c == null ? const SizedBox() : UiV2Scope(child: c),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('操作栏：三项等分铺满内容宽，图标在文字上方', (tester) async {
    final taps = <String>[];
    tester.view.physicalSize = const Size(444, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(Padding(
      padding: const EdgeInsets.symmetric(horizontal: UiV2Spacing.s4),
      child: UiV2ActionBar(
        items: [
          UiV2ActionItem(
              icon: UiV2Icons.play, label: '播放', onTap: () => taps.add('play')),
          UiV2ActionItem(
              icon: UiV2Icons.shuffle,
              label: '随机播放',
              onTap: () => taps.add('shuffle')),
          UiV2ActionItem(
              icon: UiV2Icons.more, label: '更多', onTap: () => taps.add('more')),
        ],
      ),
    )));
    await tester.pump();

    // 内容宽 444 - 16*2 = 412，三等分每份约 137.33，中心落在 16+68.7 / 16+206 / 16+343.3
    const unit = 412 / 3;
    expect(tester.getCenter(find.text('播放')).dx,
        closeTo(16 + unit * 0.5, 1.0), reason: '第一项应居中于第一等分');
    expect(tester.getCenter(find.text('随机播放')).dx,
        closeTo(16 + unit * 1.5, 1.0), reason: '第二项应居中于第二等分');
    expect(tester.getCenter(find.text('更多')).dx,
        closeTo(16 + unit * 2.5, 1.0), reason: '第三项应居中于第三等分');

    final iconY = tester.getCenter(find.byType(UiV2Icon).first).dy;
    final labelY = tester.getCenter(find.text('播放')).dy;
    expect(iconY, lessThan(labelY), reason: '图标应排在文字上方');

    await tester.tap(find.text('播放'));
    await tester.tap(find.text('随机播放'));
    await tester.tap(find.text('更多'));
    await tester.pump();
    expect(taps, ['play', 'shuffle', 'more']);
  });

  testWidgets('操作栏：颜色一律次级灰（照参考页，不做主色高亮）', (tester) async {
    await tester.pumpWidget(_wrap(const UiV2ActionBar(
      items: [
        UiV2ActionItem(icon: UiV2Icons.play, label: '播放', onTap: _noop),
      ],
    )));
    await tester.pump();
    final tone = UiV2Tokens.of(Brightness.light);
    final icon = tester.widget<UiV2Icon>(find.byType(UiV2Icon));
    expect(icon.color, tone.textDim, reason: '图标用次级灰，不用主色');
    final label = tester.widget<Text>(find.text('播放'));
    expect(label.style?.color, tone.textDim, reason: '文字用次级灰');
  });

  testWidgets('头部：封面尺寸按屏宽收缩并夹在 120–220', (tester) async {
    Future<Size> sizeAt(double width) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_wrap(const UiV2DetailHeader(
        art: SizedBox.expand(),
        type: '收藏',
        line1: '4 首 · 16 分钟',
      )));
      await tester.pump();
      return tester.getSize(find.byKey(const ValueKey('detail_header_art')));
    }

    expect(await sizeAt(444), const Size(220, 220), reason: '444 宽应取到上限 220');
    expect((await sizeAt(360)).width, closeTo(360 * 0.56, 0.5), reason: '360 宽按 56% 收缩');
    expect((await sizeAt(200)).width, 120, reason: '再窄也不低于 120');
  });

  testWidgets('头部：两行统计都渲染；次级行为空时不占位', (tester) async {
    await tester.pumpWidget(_wrap(const UiV2DetailHeader(
      art: SizedBox.expand(),
      type: '歌单 · 我的',
      line1: '3 首 · 13 分钟',
      line2: '更新于 2026-11-02',
    )));
    await tester.pump();
    expect(find.text('歌单 · 我的'), findsOneWidget);
    expect(find.text('3 首 · 13 分钟'), findsOneWidget);
    expect(find.text('更新于 2026-11-02'), findsOneWidget);

    await tester.pumpWidget(_wrap(const UiV2DetailHeader(
      art: SizedBox.expand(),
      type: '收藏',
      line1: '4 首 · 16 分钟',
    )));
    await tester.pump();
    expect(find.text('4 首 · 16 分钟'), findsOneWidget);
    expect(find.byType(UiV2ActionBar), findsNothing, reason: '没给动作就不渲染操作栏');
  });

  testWidgets('头部：文字块相对封面垂直居中（不是贴顶）', (tester) async {
    tester.view.physicalSize = const Size(444, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const UiV2DetailHeader(
      art: SizedBox.expand(),
      type: '歌单 · 我的',
      line1: '3 首 · 13 分钟',
      line2: '更新于 2026-11-02',
      actions: [
        UiV2ActionItem(icon: UiV2Icons.play, label: '播放', onTap: _noop),
      ],
    )));
    await tester.pump();

    final cover =
        tester.getRect(find.byKey(const ValueKey('detail_header_art')));
    final textTop = tester.getTopLeft(find.text('歌单 · 我的')).dy;
    final textBottom = tester.getBottomLeft(find.text('更新于 2026-11-02')).dy;
    // 文字块（首行顶 → 末行底）的中点应落在封面中线附近：
    // 贴顶排布时这里会差 70+px，就是用户报的「右侧几行太偏上」。
    expect(((textTop + textBottom) / 2 - cover.center.dy).abs(), lessThan(4),
        reason: '右侧文字块要相对封面垂直居中');
  });
}
