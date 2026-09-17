/// SearchPage 多选模式测试（阶段三 12）
///
/// 验证：
/// 1. 长按歌曲进入多选（AppBar 显示已选计数）
/// 2. 多选模式点击切换勾选、计数累加
/// 3. 关闭退出多选恢复普通模式
///
/// 模拟数据：固定 SearchState（keyword + 两条结果 + 一个来源分组）；
/// 播放器/DAO 用假实现。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:ui/ui.dart';

class _FakePlayer implements Player {
  @override
  Future<void> setQueue(List<Song> queue) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeDownloadManager implements DownloadManager {
  @override
  Future<String?> download(Song song, {String? url}) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 固定搜索状态 Notifier
class _FixedSearch extends SearchNotifier {
  final SearchState _state;

  _FixedSearch(this._state);

  @override
  SearchState build() => _state;
}

void main() {
  final songs = [
    Song(id: '1', sourceId: 'a', title: '晴天', artist: '周杰伦'),
    Song(id: '2', sourceId: 'a', title: '稻香', artist: '周杰伦'),
  ];

  testWidgets('长按进入多选，点击勾选计数，关闭退出', (tester) async {
    final container = ProviderContainer(overrides: [
      playerProvider.overrideWith((ref) => _FakePlayer()),
      downloadManagerProvider.overrideWith((ref) => _FakeDownloadManager()),
      appDatabaseProvider.overrideWith((ref) => InMemoryDatabaseProvider()),
      searchProvider.overrideWith(
        () => _FixedSearch(SearchState(
          keyword: 'q',
          allResults: songs,
          groups: [
            SearchGroup(sourceId: 'a', sourceName: '源A', songs: songs),
          ],
        )),
      ),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SearchPage()),
    ));
    await tester.pumpAndSettle();

    // 普通模式：无多选 UI
    expect(find.text('搜索歌曲、歌手'), findsOneWidget);

    // 长按第一首 → 进入多选，已选 1
    await tester.longPress(find.text('晴天'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 首'), findsOneWidget);

    // 多选模式点击第二首 → 已选 2
    await tester.tap(find.text('稻香'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 首'), findsOneWidget);

    // 再点第一首取消勾选 → 已选 1
    await tester.tap(find.text('晴天'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 首'), findsOneWidget);

    // 关闭退出多选
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('搜索歌曲、歌手'), findsOneWidget);
    expect(find.textContaining('已选'), findsNothing);
  });
}
