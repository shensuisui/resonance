/// 播放栏封面回归测试：锁定「缓存后到」时播放栏必须跟着更新
///
/// 背景：规则源（6U / 歌曲宝）的列表接口不返回封面，封面要等取详情写进
/// songs 表之后才有。于是正常时序就是「先起播（无封面）→ 一两秒后封面落库」。
/// 这里锁定两件事：
///   1. 封面还没落库时，播放栏显示占位、不报错；
///   2. 封面落库并 bump 版本后，播放栏必须换成网络图（不许停在占位）。
///
/// 模拟数据：手写假播放器（三条流显式空实现）；曲目用 const Song；
/// 缓存用 core 的 InMemoryDatabaseProvider（真实 DAO 语义，非假实现）。
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:uiv2/src/components/player_bar.dart';
import 'package:uiv2/src/design/theme.dart';
import 'package:uiv2/src/providers/providers.dart';

/// 缓存里最终会出现的封面地址
const String _coverUrl =
    'http://img4.kuwo.cn/star/albumcover/500/s4s14/96/2781088841.jpg';

/// 当前曲目快照：来自搜索列表，**没有封面**（规则源列表就是不给封面）
const Song _song = Song(
  id: 'd3ZleW5laG5qaw',
  sourceId: '6uq',
  title: 'Tell It To My Heart',
  artist: 'MEDUZA&Hozier',
);

/// 手写假播放器：只实现被 watch 的三条流，其余调用直接抛
class _FakePlayer implements Player {
  @override
  Stream<PlayerState> get stateStream => const Stream.empty();
  @override
  Stream<int> get positionStream => const Stream.empty();
  @override
  Stream<int> get durationStream => const Stream.empty();
  @override
  /// 播放栏会写 playMode / volume 等属性：一律静默忽略，
  /// 只保证被 watch 的三条流是空的（够这个测试用）
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 测试宿主：MaterialApp + UiV2Scope（注入设计 token）
Widget _host(Widget child, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: UiV2DesignTheme.dark(),
        builder: (context, child) =>
            child == null ? const SizedBox() : UiV2Scope(child: child),
        home: Scaffold(body: child),
      ),
    );

/// 播放栏当前用于展示的封面地址（没有网络图时返回 null）
String? _barCoverUrl(WidgetTester tester) {
  final finder = find.byType(CachedNetworkImage);
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<CachedNetworkImage>(finder.first).imageUrl;
}

void main() {
  testWidgets('播放栏封面：缓存还没写时是占位；写入后必须换成网络图', (tester) async {
    final db = InMemoryDatabaseProvider();
    await db.initialize();

    await tester.pumpWidget(_host(
      const UiV2PlayerBar(wide: true, tablet: true),
      [
        appDatabaseProvider.overrideWithValue(db),
        playerProvider.overrideWithValue(_FakePlayer()),
        sourceManagerProvider.overrideWithValue(SourceManager()),
        currentSongProvider.overrideWithValue(_song),
      ],
    ));
    await tester.pump();

    // 1) 缓存为空：不允许出现网络图（占位态）
    expect(_barCoverUrl(tester), isNull,
        reason: '缓存里还没有封面时不应发起网络图');

    // 2) 模拟「详情取回、封面落库」：写 songs 行 + bump 版本号
    await db.songDao.insertSong(_song.copyWith(coverUrl: _coverUrl));
    final container =
        ProviderScope.containerOf(tester.element(find.byType(UiV2PlayerBar)));
    container.read(songMetaVersionProvider.notifier).bump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    // 3) 关键断言：播放栏必须显示缓存里的封面
    expect(_barCoverUrl(tester), _coverUrl,
        reason: '封面落库后播放栏必须更新，不能停在占位');
  });

  testWidgets('播放栏封面：缓存里已经有了就直接显示（免等详情）', (tester) async {
    final db = InMemoryDatabaseProvider();
    await db.initialize();
    await db.songDao.insertSong(_song.copyWith(coverUrl: _coverUrl));

    await tester.pumpWidget(_host(
      const UiV2PlayerBar(wide: true, tablet: true),
      [
        appDatabaseProvider.overrideWithValue(db),
        playerProvider.overrideWithValue(_FakePlayer()),
        sourceManagerProvider.overrideWithValue(SourceManager()),
        currentSongProvider.overrideWithValue(_song),
      ],
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(_barCoverUrl(tester), _coverUrl);
  });

  testWidgets('播放栏封面：先写时长、后写封面（对齐真实时序）也必须更新', (tester) async {
    final db = InMemoryDatabaseProvider();
    await db.initialize();

    await tester.pumpWidget(_host(
      const UiV2PlayerBar(wide: true, tablet: true),
      [
        appDatabaseProvider.overrideWithValue(db),
        playerProvider.overrideWithValue(_FakePlayer()),
        sourceManagerProvider.overrideWithValue(SourceManager()),
        currentSongProvider.overrideWithValue(_song),
      ],
    ));
    await tester.pump();
    expect(_barCoverUrl(tester), isNull);

    final container =
        ProviderScope.containerOf(tester.element(find.byType(UiV2PlayerBar)));

    // ① 起播后播放器实测时长先落库（真实日志里这一步 cover=false）
    await db.songDao.insertSong(_song.copyWith(duration: 240));
    container.read(songMetaVersionProvider.notifier).bump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(_barCoverUrl(tester), isNull, reason: '这一步封面确实还没到');

    // ② 详情取回，封面落库（真实日志里这一步 field=meta, cover=true）
    await db.songDao.insertSong(_song.copyWith(duration: 240, coverUrl: _coverUrl));
    container.read(songMetaVersionProvider.notifier).bump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    // ③ 回归点：旧实现因 Song.== 只比 (id, sourceId) 被判为"值没变"，
    //    Riverpod 跳过通知 → 播放栏永远停在占位；这条断言必须绿。
    expect(_barCoverUrl(tester), _coverUrl,
        reason: '封面落库后播放栏必须更新（Song 相等性不含封面会吞掉这次通知）');
  });
}
