/// 路由保活回归测试：进二级页再返回，一级页不能被销毁
///
/// 现场：在「我的」页滚动一段 → 点进「设置」→ 返回 → 滚动条回到最顶。
/// 根因：_RoutedView 用"二级页替换 IndexedStack"，一级页子树被 dispose。
/// 现在二级页改为叠在一级页之上，一级页始终挂载。
///
/// 这里只断言结构（一级页在二级页显示期间仍然在树上），
/// 滚动位置本身由真机验证（同一元素返回前后 y 坐标一致）。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:uiv2/src/design/theme.dart';
import 'package:uiv2/src/pages/app_shell.dart';
import 'package:uiv2/src/pages/home_page.dart';
import 'package:uiv2/src/pages/profile_page.dart';
import 'package:uiv2/src/pages/settings_page.dart';
import 'package:uiv2/src/providers/providers.dart';
import 'package:uiv2/src/router.dart';

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
  int get currentPosition => 0;
  @override
  int get currentDuration => 0;
  @override
  double get volume => 1;
  @override
  PlayMode get playMode => PlayMode.listLoop;
  @override
  set playMode(PlayMode mode) {}
  @override
  List<Song> get queue => const [];
  @override
  int get currentIndex => -1;
  @override
  void setQueue(List<Song> songs) {}
  @override
  Future<void> play(Song song) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> next() async {}
  @override
  Future<void> previous() async {}
  @override
  Future<void> jumpToIndex(int index) async {}
  @override
  Future<void> prepareAt(int index, {Duration position = Duration.zero}) async {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('假播放器未实现该成员');
}

void main() {
  late ProviderContainer container;

  setUp(() async {
    final db = InMemoryDatabaseProvider();
    await db.initialize();
    container = ProviderContainer(overrides: <Override>[
      appDatabaseProvider.overrideWithValue(db),
      playerProvider.overrideWithValue(_FakePlayer()),
      sourceManagerProvider.overrideWithValue(SourceManager()),
      audioCacheProvider.overrideWithValue(_FakeCache()),
      recentPlaysServiceProvider
          .overrideWithValue(RecentPlaysService(db.recentPlaysDao)),
    ]);
  });

  tearDown(() => container.dispose());

  testWidgets('二级页显示期间，一级页（首页/我的）仍然挂载', (tester) async {
    tester.view.physicalSize = const Size(444, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: UiV2DesignTheme.dark(),
        builder: (context, c) => c == null ? const SizedBox() : UiV2Scope(child: c),
        home: const UiV2AppShell(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    // 先停在「我的」
    container.read(navProvider.notifier).go('profile');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ProfilePage, skipOffstage: false), findsOneWidget);

    // 进二级页（设置）：一级页不能被销毁，必须仍在树上
    container.read(navProvider.notifier).go('settings');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SettingsPage), findsOneWidget, reason: '二级页要显示');
    expect(find.byType(ProfilePage, skipOffstage: false), findsOneWidget,
        reason: '一级页必须保活，否则返回后滚动位置/状态全丢');
    expect(find.byType(HomePage, skipOffstage: false), findsOneWidget,
        reason: 'IndexedStack 里的其它一级页也应保持挂载');

    // 返回：还在「我的」
    container.read(navProvider.notifier).back();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.byType(ProfilePage, skipOffstage: false), findsOneWidget);
  });
}
