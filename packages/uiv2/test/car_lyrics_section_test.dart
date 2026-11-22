/// CarLyricsSection widget 测试
///
/// 覆盖：默认值（关闭 + 第一行）、三态切换写设置、位置切换写设置、hint 随选择变化。
/// 用 InMemorySettingsDao 驱动真实 provider（非 mock）。

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/uiv2.dart';

Future<InMemorySettingsDao> pumpSection(WidgetTester tester) async {
  final dao = InMemorySettingsDao();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [settingsDaoProvider.overrideWithValue(dao)],
      child: UiV2Theme(
        tokens: UiV2Tokens.dark,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CarLyricsSection(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return dao;
}

void main() {
  testWidgets('默认：关闭 + 第一行，hint 说明', (tester) async {
    final dao = await pumpSection(tester);
    expect(find.text('车载歌词'), findsOneWidget);
    expect(find.text('显示范围'), findsOneWidget);
    expect(find.text('歌词位置'), findsOneWidget);
    expect(find.textContaining('关闭 ·'), findsOneWidget);
    expect(find.textContaining('第一行 ·'), findsOneWidget);
    expect(await dao.get(CarLyricsSettingsKeys.scope), isNull);
    expect(await dao.get(CarLyricsSettingsKeys.slot), isNull);
  });

  testWidgets('切到「所有蓝牙」：写入 all 并更新 hint', (tester) async {
    final dao = await pumpSection(tester);
    await tester.tap(find.text('所有蓝牙'));
    await tester.pumpAndSettle();
    expect(await dao.get(CarLyricsSettingsKeys.scope), 'all');
    expect(find.textContaining('所有蓝牙 · 任意蓝牙设备都显示歌词'), findsOneWidget);
  });

  testWidgets('切到「仅车载」：写入 car', (tester) async {
    final dao = await pumpSection(tester);
    await tester.tap(find.text('仅车载'));
    await tester.pumpAndSettle();
    expect(await dao.get(CarLyricsSettingsKeys.scope), 'car');
    expect(find.textContaining('仅车载 · 连接车机时显示歌词'), findsOneWidget);
  });

  testWidgets('切到「第二行」：写入 artist，hint 改为保留歌手 - 歌名', (tester) async {
    final dao = await pumpSection(tester);
    await tester.tap(find.text('第二行'));
    await tester.pumpAndSettle();
    expect(await dao.get(CarLyricsSettingsKeys.slot), 'artist');
    expect(find.textContaining('第二行 · 保留第一行的歌手 - 歌名'), findsOneWidget);
  });
}
