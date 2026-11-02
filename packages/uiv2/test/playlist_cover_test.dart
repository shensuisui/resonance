/// 歌单封面统一实现测试（回归：同一个歌单在三个页面出现三种封面）
///
/// 现场：默认1 这个歌单在「自建歌曲」标签页是单图铺满（外来的封面）、
/// 在「全部歌单」是 2×2 缺两个格子、在详情页是 2×2 四张齐全。
///
/// 根因：封面列表被 4+ 处各写了一遍（有的只读快照并过滤空值、有的走统一回落、
/// 有的用 map 顺序），卡片自身还会在"没有封面"时退化成单图铺满。
///
/// 这里钉住统一后的行为：
///   ① 按 songKeys 顺序取前 4 首；缺封面的留空位（不挤动后面的格子）；
///   ② 卡片页（只有快照）与详情页（有完整曲目）得到同一组封面；
///   ③ 自有歌单永远用拼贴（4 格），不再退化成单图；远端歌单才用官方单图。
///
/// 模拟数据：手工构造 Playlist + 四首曲目快照（其中第 3 首故意没封面）。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/components/rows.dart';
import 'package:uiv2/src/design/theme.dart';
import 'package:uiv2/src/providers/providers.dart';

/// 四首曲目（第 3 首无封面，用于验证"留空位"）
const _s1 = Song(id: '1', sourceId: 's', title: '可不可以', artist: '张紫豪',
    coverUrl: 'http://c/1.jpg');
const _s2 = Song(id: '2', sourceId: 's', title: '赤伶', artist: 'HITA',
    coverUrl: 'http://c/2.jpg');
const _s3 = Song(id: '3', sourceId: 's', title: '辞·九门回忆', artist: '冰幽&解忧草');
const _s4 = Song(id: '4', sourceId: 's', title: '幻听', artist: '许嵩',
    coverUrl: 'http://c/4.jpg');

/// 歌单：快照里只有 1/2/4 有封面（第 3 首缺）
Playlist _playlist({String? coverUrl}) => Playlist(
      id: 'p1',
      name: '默认1',
      songKeys: const ['s:1', 's:2', 's:3', 's:4'],
      songSnapshots: const {
        's:1': _s1,
        's:2': _s2,
        's:3': _s3,
        's:4': _s4,
      },
      coverUrl: coverUrl,
      createdTime: DateTime(2026, 11, 2),
      modifiedTime: DateTime(2026, 11, 2),
    );

/// 宿主：ProviderScope + 主题（与其它组件测试一致）
Widget _host(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: UiV2DesignTheme.dark(),
        builder: (context, c) => c == null ? const SizedBox() : UiV2Scope(child: c),
        home: Scaffold(body: child),
      ),
    );

void main() {
  group('resolvePlaylistCovers（唯一实现）', () {
    testWidgets('按曲目顺序取前 4 首，缺封面留空位而不是挤动后面的格子', (tester) async {
      late List<String> covers;
      await tester.pumpWidget(_host(Consumer(builder: (context, ref, _) {
        covers = resolvePlaylistCovers(ref, _playlist());
        return const SizedBox();
      })));
      await tester.pump();

      expect(covers.length, 4);
      expect(covers[0], 'http://c/1.jpg');
      expect(covers[1], 'http://c/2.jpg');
      expect(covers[2], '', reason: '第 3 首没有封面 → 留空位（补位色），不能把第 4 首挤过来');
      expect(covers[3], 'http://c/4.jpg');
    });

    testWidgets('卡片页（只有快照）与详情页（有完整曲目）得到同一组封面', (tester) async {
      late List<String> fromSnapshots;
      late List<String> fromSongs;
      await tester.pumpWidget(_host(Consumer(builder: (context, ref, _) {
        fromSnapshots = resolvePlaylistCovers(ref, _playlist());
        fromSongs = resolvePlaylistCovers(ref, _playlist(),
            songs: const [_s1, _s2, _s3, _s4]);
        return const SizedBox();
      })));
      await tester.pump();

      expect(fromSongs, fromSnapshots, reason: '同一个歌单在任何页面都必须得到同一组封面');
    });
  });

  group('歌单卡片封面样式', () {
    testWidgets('自有歌单即使有 coverUrl 也用拼贴（不再单图铺满）', (tester) async {
      await tester.pumpWidget(_host(UiV2PlaylistCard(
        playlist: _playlist(coverUrl: 'http://c/foreign.jpg'),
        owned: true,
        covers: const <String>[],
        onTap: () {},
        onPlay: () {},
      )));
      await tester.pump();

      expect(find.byType(UiV2Mosaic), findsOneWidget,
          reason: '自有歌单统一拼贴：缺封面也该是 4 格补位色，而不是外来的单图');
      expect(find.byType(UiV2Cover), findsNothing);
    });

    testWidgets('远端歌单（无曲目、只有官方封面）才用单图', (tester) async {
      await tester.pumpWidget(_host(UiV2PlaylistCard(
        playlist: _playlist(coverUrl: 'http://c/remote.jpg'),
        covers: const <String>[],
        onTap: () {},
        onPlay: () {},
      )));
      await tester.pump();

      expect(find.byType(UiV2Cover), findsOneWidget);
      expect(find.byType(UiV2Mosaic), findsNothing);
    });
  });
}
