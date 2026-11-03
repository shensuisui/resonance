/// 「离线可播 / 已下载」标记 + 源角标的回归测试
///
/// 这几条守的都是**看不到但很容易写坏**的东西：
///   ① 两个图标的挖空靠 nonZero 下的反向绕行 —— 绕向写反，内符就消失、两个图标
///      退化成一模一样的实心盘；所以用**像素采样**验证「盘面实心、盘心是洞」。
///   ② 挖空内符的外接框中心必须恰在圆盘中心 (12,12)（几何构造保证，不能靠肉眼）。
///   ③ 行内：标记在**歌手前面**、只有图标没有文字胶囊；源图标移到封面角标。
library;

import 'dart:ui' as ui;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:uiv2/src/components/rows.dart';
import 'package:uiv2/src/components/source_icon.dart';
import 'package:uiv2/src/design/icons.dart';
import 'package:uiv2/src/design/theme.dart';
import 'package:uiv2/src/design/tokens.dart';
import 'package:uiv2/src/providers/providers.dart';

/// 假播放缓存
class _FakeCache implements AudioCache {
  @override
  Future<void> init() async {}
  @override
  Set<String> get cachedKeys => const {};
  @override
  bool isCached(String songKey) => false;
  @override
  String? localUrlFor(String songKey) => null;
  @override
  Future<String?> downloadedUrlFor(Song song) async => null;
  @override
  Future<void> cacheAfterPlay(Song song, String url,
      {Map<String, String>? headers}) async {}
  @override
  Future<int> sizeOnDisk() async => 0;
  @override
  Future<void> clear() async {}
  @override
  Stream<void> get changes => const Stream.empty();
}

/// 假播放器
class _FakePlayer implements Player {
  @override
  Stream<PlayerState> get stateStream => const Stream.empty();
  @override
  Stream<int> get positionStream => const Stream.empty();
  @override
  Stream<int> get durationStream => const Stream.empty();
  @override
  PlayerState get currentState => PlayerState.idle;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('假播放器未实现该成员');
}

/// 取出图标里「挖空内符」那一段（第二个 M 开始）
String _glyphPart(String rawD) {
  final at = rawD.indexOf('M', 1);
  expect(at, greaterThan(0), reason: '图标应含两段路径（外圈 + 内符）');
  return rawD.substring(at);
}

void main() {
  const song = Song(
    id: 'x',
    sourceId: 'stub',
    title: '赤伶',
    artist: 'HITA',
    duration: 266,
  );

  group('图标几何', () {
    test('两个图标都已登记，且外圈是 24 格里的实心圆', () {
      for (final name in [UiV2Icons.offlineReady, UiV2Icons.downloaded]) {
        final raw = debugIconRawD(name);
        expect(raw, isNotNull, reason: '$name 应已加入图标目录');
        final disc = debugParseIconPath(raw!.substring(0, _glyphPart(raw).length == 0
            ? raw.length
            : raw.indexOf('M', 1)));
        final b = disc.getBounds();
        expect(b.center.dx, closeTo(12, 0.3), reason: '$name 圆盘应居中');
        expect(b.center.dy, closeTo(12, 0.3), reason: '$name 圆盘应居中');
        expect(b.width, closeTo(17.2, 0.3), reason: '$name 圆盘直径应为 17.2');
      }
    });

    test('挖空内符的外接框中心恰为圆盘中心 (12,12)', () {
      for (final name in [UiV2Icons.offlineReady, UiV2Icons.downloaded]) {
        final b = debugParseIconPath(_glyphPart(debugIconRawD(name)!)).getBounds();
        expect(b.center.dx, closeTo(12, 0.02), reason: '$name 内符水平未居中');
        expect(b.center.dy, closeTo(12, 0.02), reason: '$name 内符垂直未居中');
      }
    });

    test('两个图标的内符不是同一个形状（否则等于同一个图标）', () {
      final a = _glyphPart(debugIconRawD(UiV2Icons.offlineReady)!);
      final b = _glyphPart(debugIconRawD(UiV2Icons.downloaded)!);
      expect(a, isNot(b));
    });

    testWidgets('挖空真的成洞：盘面不透明、盘心透明（绕向写反就会失败）', (tester) async {
      await tester.runAsync(() async {
        const scale = 8;
        const side = 24 * scale;
        for (final name in [UiV2Icons.offlineReady, UiV2Icons.downloaded]) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.scale(scale.toDouble());
          canvas.drawPath(
            debugParseIconPath(debugIconRawD(name)!),
            Paint()
              ..color = const Color(0xFFFFFFFF)
              ..style = PaintingStyle.fill
              ..isAntiAlias = false,
          );
          final img = await recorder.endRecording().toImage(side, side);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
          int alphaAt(double x, double y) {
            final px = (x * scale).round();
            final py = (y * scale).round();
            return bytes!.getUint8((py * side + px) * 4 + 3);
          }

          expect(alphaAt(12, 5.6), greaterThan(200),
              reason: '$name 盘面（内符上方）应是实心不透明');
          expect(alphaAt(12, 12), lessThan(40),
              reason: '$name 盘心应是挖空的洞 —— 绕向反了会整块实心，两个图标就分不出来了');
        }
      });
    });
  });

  group('歌曲行', () {
    late ProviderContainer container;

    Future<void> pumpRow(WidgetTester tester, Song s,
        {bool offline = false, bool withArt = true}) async {
      final db = InMemoryDatabaseProvider();
      await db.initialize();
      container = ProviderContainer(overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        playerProvider.overrideWithValue(_FakePlayer()),
        sourceManagerProvider.overrideWithValue(SourceManager()),
        audioCacheProvider.overrideWithValue(_FakeCache()),
        if (offline) offlineAvailableProvider(s.globalKey).overrideWithValue(true),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: UiV2DesignTheme.dark(),
          builder: (context, c) =>
              c == null ? const SizedBox() : UiV2Scope(child: c),
          home: Scaffold(
            body: UiV2SongRow(
              song: s,
              index: 0,
              showArt: withArt,
              onTap: () {},
              onToggleLike: () {},
              onMore: () {},
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    Finder markOf(String name) => find.byWidgetPredicate(
        (w) => w is UiV2Icon && w.name == name);

    testWidgets('已下载：绿色对勾图标在歌手**前面**，且没有文字胶囊', (tester) async {
      await pumpRow(tester, song.copyWith(localPath: 'F:\\\\a.mp3'));
      final t = UiV2Tokens.of(Brightness.dark);

      expect(markOf(UiV2Icons.downloaded), findsOneWidget);
      final mark = tester.widget<UiV2Icon>(markOf(UiV2Icons.downloaded));
      expect(mark.color, t.ok, reason: '已下载用绿色 ok 调');
      expect(mark.size, 16, reason: '前置标记定为 16px');
      expect(tester.getCenter(markOf(UiV2Icons.downloaded)).dx,
          lessThan(tester.getCenter(find.text('HITA')).dx),
          reason: '标记要在歌手前面');
      // 旧的文字胶囊必须消失
      expect(find.text('已下载'), findsNothing);
      expect(find.text('离线可播'), findsNothing);
      // 源图标进封面角标
      expect(find.byType(UiV2SourceBadge), findsOneWidget);
    });

    testWidgets('离线可播：灰色箭头图标在歌手前，无角标文字', (tester) async {
      await pumpRow(tester, song, offline: true);
      final t = UiV2Tokens.of(Brightness.dark);

      expect(markOf(UiV2Icons.offlineReady), findsOneWidget);
      expect(
          tester.widget<UiV2Icon>(markOf(UiV2Icons.offlineReady)).color,
          t.textDim,
          reason: '离线可播保持次级灰');
      expect(tester.getCenter(markOf(UiV2Icons.offlineReady)).dx,
          lessThan(tester.getCenter(find.text('HITA')).dx));
      expect(find.byType(UiV2SourceBadge), findsOneWidget);
    });

    testWidgets('都没有：两个标记都不出现（但源角标仍在）', (tester) async {
      await pumpRow(tester, song);
      expect(markOf(UiV2Icons.downloaded), findsNothing);
      expect(markOf(UiV2Icons.offlineReady), findsNothing);
      expect(find.byType(UiV2SourceBadge), findsOneWidget);
    });

    testWidgets('无封面（本地缺封面的行）：退回行内源图标，且不出现角标', (tester) async {
      await pumpRow(tester, song, withArt: false);
      expect(find.byType(UiV2SourceBadge), findsNothing,
          reason: '没有封面就没有地方压角标');
      expect(find.byType(UiV2SourceIcon), findsOneWidget,
          reason: '退回行内源图标，否则这一行的来源信息就丢了');
    });
  });
}
