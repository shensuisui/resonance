/// 拖拽返回后 go_router URL 必须同步回退（验收第 6 条）
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:uiv2/src/app_router.dart';
import 'package:uiv2/src/design/theme.dart';
import 'package:uiv2/src/route/card_page.dart';
import 'package:uiv2/src/pages/settings_page.dart';
import 'package:uiv2/src/providers/providers.dart';
import 'package:uiv2/src/router.dart';

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
  Future<void> cacheAfterPlay(Song song, String url, {Map<String, String>? headers}) async {}
  @override
  Future<int> sizeOnDisk() async => 0;
  @override
  Future<void> clear() async {}
  @override
  Stream<void> get changes => const Stream.empty();
}

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
}

void main() {
  testWidgets('push 设置后横向拖拽返回，URL 回到来源页', timeout: const Timeout(Duration(seconds: 40)), (tester) async {
    tester.view.physicalSize = const Size(444, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final db = InMemoryDatabaseProvider();
    await db.initialize();
    final container = ProviderContainer(overrides: <Override>[
      appDatabaseProvider.overrideWithValue(db),
      playerProvider.overrideWithValue(_FakePlayer()),
      sourceManagerProvider.overrideWithValue(SourceManager()),
      audioCacheProvider.overrideWithValue(_FakeCache()),
      recentPlaysServiceProvider.overrideWithValue(RecentPlaysService(db.recentPlaysDao)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: container.read(appRouterProvider),
        theme: UiV2DesignTheme.dark(),
        builder: (context, c) => c == null ? const SizedBox() : UiV2Scope(child: c),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 700));

    container.read(navProvider.notifier).go('settings');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(SettingsPage), findsOneWidget);
    final router = container.read(appRouterProvider);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/profile/settings');

    // 手势识别器由真机录屏验证；这里直接驱动同一套 route 逻辑，验证 pop 与 URL 同步
    final route = ModalRoute.of(tester.element(find.byType(SettingsPage)))!
        as CardPageRoute<void>;
    route.handleDragStart();
    route.handleDragUpdate(320, 444);
    unawaited(route.handleDragEnd(0, 444));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();

    expect(find.byType(SettingsPage), findsNothing);
    expect(container.read(navProvider).current.name, 'home');
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
  });
}
