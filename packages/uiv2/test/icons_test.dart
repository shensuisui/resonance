/// 图标集回归测试（lib/src/design/icons.dart）。
///
/// 测什么：
///   * 抽查代表图标名（含历史上出过故障的 heart / user）调用 [UiV2Icon]
///     能正常 pump 且 takeException 为 null —— 覆盖 _parseSvgPath 的
///     SVG path 子集解析（小数连写 l.8.8.8-.8、相对 s 命令、圆弧 a 等）；
///   * 通过公开的 [debugParseIconPath] 直接验证两条历史回归路径
///     能解析出有效 Path（不抛 FormatException、不死循环）。
///
/// 模拟数据来源：icons.dart 内置 _catalog 路径配表（经 UiV2Icons 常量访问）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/design/icons.dart';

void main() {
  // 抽查的代表图标：覆盖 fill/stroke 两种模式、含小数连写与 s/a 命令的路径
  const sampleIcons = [
    'home',
    'search',
    'user', // 历史：含相对圆弧命令（曾死循环）
    'play',
    'pause',
    'shuffle',
    'repeat',
    'heart', // 历史：小数连写 l.8.8.8-.8（曾 FormatException）
    'volume',
    'info',
  ];

  testWidgets('抽查 10 个代表图标都能 pump 且无异常', (tester) async {
    for (final name in sampleIcons) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: UiV2Icon(name))),
        ),
      );
      // 图标本身无动画，单帧 pump 即可
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '图标 $name 渲染失败');
      expect(find.byType(UiV2Icon), findsOneWidget);
    }
  });

  testWidgets('UiV2Icons 全部 38 个常量逐一渲染无异常', (tester) async {
    const all = [
      UiV2Icons.home, UiV2Icons.search, UiV2Icons.library, UiV2Icons.user,
      UiV2Icons.play, UiV2Icons.pause, UiV2Icons.prev, UiV2Icons.next,
      UiV2Icons.shuffle, UiV2Icons.repeat, UiV2Icons.repeatOne,
      UiV2Icons.heart, UiV2Icons.heartFill, UiV2Icons.chevronDown,
      UiV2Icons.chevronRight, UiV2Icons.expand, UiV2Icons.arrowLeft,
      UiV2Icons.more, UiV2Icons.edit, UiV2Icons.trash, UiV2Icons.queue,
      UiV2Icons.lyrics, UiV2Icons.volume, UiV2Icons.volumeMute,
      UiV2Icons.plus, UiV2Icons.download, UiV2Icons.check, UiV2Icons.close,
      UiV2Icons.folder, UiV2Icons.globe, UiV2Icons.clock, UiV2Icons.note,
      UiV2Icons.disc, UiV2Icons.share, UiV2Icons.info, UiV2Icons.device,
      UiV2Icons.sun, UiV2Icons.moon,
    ];
    expect(all.length, 38);
    for (final name in all) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: UiV2Icon(name, size: 24))),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '图标 $name 渲染失败');
    }
  });

  group('debugParseIconPath 解析回归', () {
    test('heart 路径（小数连写 l.8.8.8-.8）能解析且不抛异常', () {
      // 历史故障：贪心吞小数点导致 double.parse 抛 FormatException
      const d = 'M12 20.4 4.6 13a4.7 4.7 0 0 1 6.6-6.7l.8.8.8-.8A4.7 4.7 0 0 1 19.4 13z';
      final path = debugParseIconPath(d);
      expect(path.getBounds(), isNotNull);
      // 路径应有内容（非空边界）
      expect(path.getBounds().isEmpty, isFalse);
    });

    test('user 路径（相对 s 命令）能解析且收敛（不死循环）', () {
      // 历史故障：s 分支缺失后游标越界死循环；若死循环本测试会超时失败
      const d1 = 'M15.6 8.2a3.6 3.6 0 1 1-7.2 0 3.6 3.6 0 0 1 7.2 0z';
      const d2 = 'M5 20.2c0-3.4 3.1-5.8 7-5.8s7 2.4 7 5.8';
      final p1 = debugParseIconPath(d1);
      final p2 = debugParseIconPath(d2);
      expect(p1.getBounds().isEmpty, isFalse);
      expect(p2.getBounds().isEmpty, isFalse);
    });

    test('常见命令混合（M/L/H/V/C/Z 与相对形式）都能解析', () {
      final p = debugParseIconPath('M2 6h1.97v3.3H22v-1a4 4 0 0 1 4-4z');
      expect(p.getBounds(), isNotNull);
    });

    test('空串与非法 token 不抛异常（安全收敛）', () {
      expect(debugParseIconPath('').getBounds(), isNotNull);
      // 非法 token：解析器应跳过而不是崩溃
      expect(debugParseIconPath('M10 10 X Y Z').getBounds(), isNotNull);
    });
  });
}
