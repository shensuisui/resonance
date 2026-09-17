/// DiscoverPage 首页化测试（阶段三 15）
///
/// 验证：
/// 1. 有最近播放时显示「最近播放」横滑区
/// 2. 显示「音乐源管理」快捷入口
/// 3. 推荐歌单网格渲染
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:ui/ui.dart';

class _FixedDiscover extends DiscoverNotifier {
  final DiscoverState _state;

  _FixedDiscover(this._state);

  @override
  DiscoverState build() => _state;
}

class _FixedRecent extends RecentPlaysNotifier {
  final List<Song> _songs;

  _FixedRecent(this._songs);

  @override
  List<Song> build() => _songs;
}

void main() {
  final recent = [
    Song(id: '1', sourceId: 'a', title: '晴天', artist: '周杰伦'),
    Song(id: '2', sourceId: 'a', title: '稻香', artist: '周杰伦'),
  ];
  final playlist = Playlist(
    id: 'pl1',
    name: '华语经典',
    songKeys: const [],
    createdTime: DateTime(2026),
    modifiedTime: DateTime(2026),
  );

  testWidgets('最近播放区 + 快捷入口 + 歌单网格渲染', (tester) async {
    final container = ProviderContainer(overrides: [
      discoverProvider.overrideWith(
        () => _FixedDiscover(DiscoverState(playlists: [playlist])),
      ),
      recentPlaysProvider.overrideWith(() => _FixedRecent(recent)),
      playerProvider.overrideWith((ref) => _NoopPlayer()),
      appDatabaseProvider.overrideWith((ref) => InMemoryDatabaseProvider()),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DiscoverPage()),
    ));
    await tester.pumpAndSettle();

    // 最近播放横滑区
    expect(find.text('最近播放'), findsOneWidget);
    expect(find.text('晴天'), findsWidgets);

    // 快捷入口
    expect(find.text('音乐源管理'), findsOneWidget);

    // 歌单网格
    expect(find.text('华语经典'), findsOneWidget);
  });

  testWidgets('无最近播放时只显示快捷入口与歌单', (tester) async {
    final container = ProviderContainer(overrides: [
      discoverProvider.overrideWith(
        () => _FixedDiscover(DiscoverState(playlists: [playlist])),
      ),
      recentPlaysProvider.overrideWith(() => _FixedRecent(const [])),
      playerProvider.overrideWith((ref) => _NoopPlayer()),
      appDatabaseProvider.overrideWith((ref) => InMemoryDatabaseProvider()),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DiscoverPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('最近播放'), findsNothing);
    expect(find.text('音乐源管理'), findsOneWidget);
    expect(find.text('华语经典'), findsOneWidget);
  });
}

class _NoopPlayer implements Player {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
