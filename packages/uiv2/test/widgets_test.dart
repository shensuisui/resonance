/// 组件冒烟测试（lib/src/components/）。
///
/// 测什么：
///   * 每个组件 pump 一次 + takeException isNull：
///     UiV2Panel / UiV2Empty（含 actions 回调）/ UiV2Chip 选中态 /
///     UiV2Switch 切换回调 / UiV2Button disabled 态 / UiV2Badge 三色 /
///     UiV2Segmented 切换 / UiV2Eq 固定帧（repeat 动画禁止 pumpAndSettle）/
///     UiV2SongRow 渲染标题与歌手 + 点击回调；
///   * UiV2SongRow 是 ConsumerWidget：需要 ProviderScope 与
///     appDatabaseProvider/playerProvider/sourceManagerProvider override。
///
/// 模拟数据来源：手工构造 core Song；providers 用 InMemoryDatabaseProvider
/// 与手写 _FakePlayer（三条流显式 const Stream.empty()，其余 noSuchMethod）。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/components/rows.dart';
import 'package:uiv2/src/components/surfaces.dart';
import 'package:uiv2/src/design/theme.dart';
import 'package:uiv2/src/providers/providers.dart';
// Riverpod 3.4 的 Override 类型只从 riverpod/misc.dart 导出
import 'package:riverpod/misc.dart' show Override;

/// 手写假播放器（同 providers_test.dart：三条流显式空实现）
class _FakePlayer implements Player {
  @override
  Stream<PlayerState> get stateStream => const Stream.empty();
  @override
  Stream<int> get positionStream => const Stream.empty();
  @override
  Stream<int> get durationStream => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// 统一测试宿主：MaterialApp + UiV2Scope（注入 UiV2Tokens）+ Riverpod
Widget _host(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: UiV2DesignTheme.dark(),
      builder: (context, child) =>
          child == null ? const SizedBox() : UiV2Scope(child: child),
      home: Scaffold(body: child),
    ),
  );
}

ProviderContainer _makeContainer() => ProviderContainer(overrides: [
  appDatabaseProvider.overrideWithValue(InMemoryDatabaseProvider()),
  playerProvider.overrideWithValue(_FakePlayer()),
  sourceManagerProvider.overrideWithValue(SourceManager()),
]);

void main() {
  group('静态组件（无动画，pumpAndSettle 安全）', () {
    testWidgets('UiV2Panel 渲染子组件且无异常', (tester) async {
      await tester.pumpWidget(_host(const UiV2Panel(child: Text('面板内容'))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('面板内容'), findsOneWidget);
    });

    testWidgets('UiV2Empty 基础渲染 + actions 回调可点', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_host(UiV2Empty(
        title: '还没有歌曲',
        text: '去添加一些吧',
        actions: UiV2Button(label: '去逛逛', onTap: () => tapped = true),
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('还没有歌曲'), findsOneWidget);
      expect(find.text('去添加一些吧'), findsOneWidget);
      await tester.tap(find.text('去逛逛'));
      expect(tapped, isTrue);
    });

    testWidgets('UiV2Chip 选中/未选中两态渲染，回调触发', (tester) async {
      var tapped = false;
      // 未选中态
      await tester.pumpWidget(_host(UiV2Chip(
        label: '流行',
        selected: false,
        onTap: () => tapped = true,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('流行'), findsOneWidget);
      await tester.tap(find.text('流行'));
      expect(tapped, isTrue);

      // 选中态
      tapped = false;
      await tester.pumpWidget(_host(UiV2Chip(
        label: '摇滚',
        selected: true,
        onTap: () => tapped = true,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('摇滚'));
      expect(tapped, isTrue);
    });

    testWidgets('UiV2Switch 切换回调带上新值', (tester) async {
      var value = false;
      late StateSetter setHostState;
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (context, setState) {
          setHostState = setState;
          return UiV2Switch(
            value: value,
            semanticLabel: '仅 Wi-Fi 下载',
            onChanged: (v) => setHostState(() => value = v),
          );
        },
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(value, isFalse);
      await tester.tap(find.byType(UiV2Switch));
      await tester.pumpAndSettle();
      expect(value, isTrue);
      // 回调为 null 时不崩
      await tester.pumpWidget(
          _host(const UiV2Switch(value: true, onChanged: null)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('UiV2Button disabled 态：不响应点击', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_host(UiV2Button(
        label: '不可点',
        onTap: null,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // disabled（onTap=null）时 tap 不触发任何回调
      await tester.tap(find.text('不可点'), warnIfMissed: false);
      expect(tapped, isFalse);

      // enabled 态回调触发
      await tester.pumpWidget(_host(UiV2Button(
        label: '可点',
        onTap: () => tapped = true,
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('可点'));
      expect(tapped, isTrue);
    });

    testWidgets('UiV2Badge 三种色调都能渲染', (tester) async {
      for (final tone in UiV2BadgeTone.values) {
        await tester.pumpWidget(_host(UiV2Badge(
          label: tone.name,
          tone: tone,
          icon: 'check',
        )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tone.name);
        expect(find.text(tone.name), findsOneWidget);
      }
    });

    testWidgets('UiV2Segmented 切换回调带回新 id', (tester) async {
      var selected = 'a';
      late StateSetter setHostState;
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (context, setState) {
          setHostState = setState;
          return UiV2Segmented(
            options: const [('a', '选项 A'), ('b', '选项 B')],
            value: selected,
            onChanged: (id) => setHostState(() => selected = id),
          );
        },
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('选项 B'));
      await tester.pumpAndSettle();
      expect(selected, 'b');
    });
  });

  group('动画组件（repeat 动画：只用固定帧 pump）', () {
    testWidgets('UiV2Eq 固定帧 pump 不抛异常', (tester) async {
      await tester.pumpWidget(
          _host(UiV2Eq(color: const Color(0xFFFFFFFF))));
      // repeat 动画永不 settle：只 pump 固定帧
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      // animated=false 时静止渲染
      await tester.pumpWidget(_host(UiV2Eq(
        color: const Color(0xFFFFFFFF),
        animated: false,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('UiV2SongRow 渲染标题与歌手 + 点击回调（含 Eq 动画固定帧）',
        (tester) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      var rowTapped = false;
      var likeTapped = false;
      var moreTapped = false;
      final song = const Song(
        id: 'midnights#3',
        sourceId: 'demo_catalog',
        title: 'Anti-Hero',
        artist: 'Taylor Swift',
        album: 'Midnights',
        duration: 200,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: UiV2DesignTheme.dark(),
            builder: (context, child) =>
                child == null ? const SizedBox() : UiV2Scope(child: child),
            home: Scaffold(
              body: UiV2SongRow(
                song: song,
                index: 2,
                onTap: () => rowTapped = true,
                onToggleLike: () => likeTapped = true,
                onMore: () => moreTapped = true,
              ),
            ),
          ),
        ),
      );
      // 行内含潜在动画组件：固定帧 pump
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(find.text('Anti-Hero'), findsOneWidget);
      expect(find.textContaining('Taylor Swift'), findsOneWidget);

      // 点击行 -> onTap
      await tester.tap(find.text('Anti-Hero'));
      expect(rowTapped, isTrue);

      // 点击喜欢按钮（semantics 标签定位）
      await tester.tap(find.bySemanticsLabel('喜欢'));
      expect(likeTapped, isTrue);

      // 点击更多按钮
      await tester.tap(find.bySemanticsLabel('更多操作：Anti-Hero'));
      expect(moreTapped, isTrue);
    });
  });
}
