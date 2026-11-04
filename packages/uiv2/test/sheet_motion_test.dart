/// 底部弹层动效与键盘让位回归测试（Issue #5 第 4、5 条）
///
/// 现场：
///   * 蒙层不渐隐渐显，而是跟着弹层整页从下往上滑（旧实现把蒙层放进同一页
///     用 SlideTransition 带着走）；
///   * 弹层不跟手 —— 拖不动，也没有下拉关闭；
///   * 键盘弹出直接盖住弹层底部的输入框（新建歌单等表单）。
///
/// 现在的口径：
///   * 蒙层 [FadeTransition] 路由动画渐入渐出，位置全程铺满，不再整体滑动；
///   * 面板窄屏从下滑入，拖拽跟手，松手按位移/速度决定关闭或弹回；
///   * 键盘弹出时弹层整体抬到键盘以上（viewInsets）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/components/sheets.dart';
import 'package:uiv2/src/design/tokens.dart';
import 'package:uiv2/src/design/theme.dart';

void main() {
  // 视口 444×900（窄屏）：测试里 dpr=1，900 即逻辑屏高
  const screenH = 900.0;

  Future<void> pumpHarness(WidgetTester tester) async {
    tester.view.physicalSize = const Size(444, screenH);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: UiV2DesignTheme.dark(),
        // UiV2Theme 要注在 builder 里（Navigator 之上）：弹层是独立路由，
        // 放在 home 里路由子树继承不到令牌（真实应用也是 UiV2Scope 包在 builder）
        builder: (context, child) => UiV2Theme(
          tokens: UiV2Tokens.dark,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  key: const Key('open-sheet'),
                  onPressed: () => showUiV2Sheet(
                    context,
                    title: '测试弹层',
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 内容要超过弹层最大高度（0.82×屏高），
                        // 让「弹层底边」这个断言有明确落点
                        for (var i = 0; i < 45; i++) Text('填充行 $i'),
                        const TextField(
                          key: Key('sheet-input'),
                          decoration: InputDecoration(hintText: '输入框'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('打开弹层'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
  }

  /// 弹层容器（surface 底色在测试内容里唯一，可直接按颜色定位）
  Rect sheetRect(WidgetTester tester) {
    final finder = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).color == UiV2Tokens.dark.surface,
    );
    return tester.getRect(finder.first);
  }

  /// 蒙层容器（scrim 颜色唯一）
  Finder scrimFinder() => find.byWidgetPredicate(
    (w) => w is Container && w.color == UiV2Tokens.dark.scrim,
  );

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('open-sheet')));
    // 起帧让入场动画启动，再推满 d3=300ms
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets('蒙层渐显且铺满全屏，不再跟着面板整体滑动', (tester) async {
    await pumpHarness(tester);
    await tester.tap(find.byKey(const Key('open-sheet')));
    // 动画进行到约 1/3：蒙层应该已经出现（渐入中）且铺满全屏
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final scrimMid = scrimFinder();
    expect(scrimMid, findsOneWidget, reason: '蒙层应该在入场早期就出现');
    final scrimRect = tester.getRect(scrimMid);
    expect(scrimRect.top, 0, reason: '蒙层从第一帧就铺满全屏（渐隐渐显，不是滑动进场）');
    expect(scrimRect.bottom, screenH);

    // 蒙层包在 FadeTransition 里且此刻还没到全不透明 → 确实是渐入
    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: scrimMid, matching: find.byType(FadeTransition)).first,
    );
    expect(fade.opacity.value, greaterThan(0), reason: '入场中途蒙层已经开始渐显');
    expect(fade.opacity.value, lessThan(1), reason: '入场中途蒙层尚未完全显形');

    // 动画结束：蒙层全显
    await tester.pump(const Duration(milliseconds: 350));
    expect(fade.opacity.value, 1, reason: '入场结束后蒙层完全显形');
  });

  testWidgets('面板从下滑入：入场中途位置低于终态', (tester) async {
    await pumpHarness(tester);
    await tester.tap(find.byKey(const Key('open-sheet')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final topMid = sheetRect(tester).top;
    await tester.pump(const Duration(milliseconds: 350));
    final topEnd = sheetRect(tester).top;

    expect(topMid, greaterThan(topEnd + 50), reason: '入场中途面板应在终态下方（从下滑入）');
    expect(topEnd, lessThan(screenH / 2), reason: '终态面板贴在屏幕下部');
  });

  testWidgets('拖拽跟手：面板跟着手指下移，小幅拖拽松手弹回原位', (tester) async {
    await pumpHarness(tester);
    await openSheet(tester);
    final topBefore = sheetRect(tester).top;

    // 在标题行（弹层头部，不在滚动区里）按下往下拖 200px
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('测试弹层')),
    );
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    final topDragged = sheetRect(tester).top;
    expect(topDragged, greaterThan(topBefore + 100), reason: '拖拽过程中面板应跟手下移');

    // 松手：位移不足阈值 → 弹回原位，弹层仍开着
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('测试弹层'), findsOneWidget, reason: '小幅拖拽松手应弹回而不是关闭');
    final topRestored = sheetRect(tester).top;
    expect((topRestored - topBefore).abs(), lessThan(5), reason: '弹回后回到原位');
  });

  testWidgets('拖拽超过阈值松手：关闭弹层', (tester) async {
    await pumpHarness(tester);
    await openSheet(tester);

    // 往下拖 400px（面板高约 0.82×900=738，进度约 0.54 > 0.3）
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('测试弹层')),
    );
    await gesture.moveBy(const Offset(0, 400));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('测试弹层'), findsNothing, reason: '拖拽超过阈值松手应关闭弹层');
  });

  testWidgets('键盘弹出：弹层整体抬到键盘以上，输入框不被盖住', (tester) async {
    await pumpHarness(tester);
    await openSheet(tester);

    const keyboardH = 300.0;
    expect(sheetRect(tester).bottom, screenH, reason: '没有键盘时弹层底边贴屏幕底');

    // 模拟键盘弹出（edge-to-edge 下窗口不 resize，viewInsets 才带键盘高度）
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardH);
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();

    final lifted = sheetRect(tester);
    expect(
      lifted.bottom,
      closeTo(screenH - keyboardH, 1),
      reason: '键盘弹出后弹层底边应抬到键盘上沿',
    );
    expect(lifted.top, greaterThanOrEqualTo(0), reason: '弹层不能被顶出屏幕');
  });
}
