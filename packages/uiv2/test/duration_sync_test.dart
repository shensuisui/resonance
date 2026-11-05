/// 时长回写目标竞态回归测试。
///
/// 背景：Android 上 durationStream 往往在 currentTrackId 落地之前到达，
/// 旧的 duration 回写逻辑用 currentSongProvider（指向上一首）选目标，
/// 会把新曲时长写到旧曲，或因为旧曲已有 duration 而整条跳过。
/// 修复后优先用播放器当前正在装载的队列项（currentIndex 指向的那首）。
library;

import 'dart:async';
import 'dart:core';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/providers/providers.dart';

class _RacePlayer implements Player, CurrentSongSource, AudibleSongSource {
  final durationCtrl = StreamController<int>.broadcast();
  final songCtrl = StreamController<Song?>.broadcast();

  @override
  Song? audibleSong;

  @override
  List<Song> queue = [];

  @override
  int currentIndex = 0;

  @override
  Stream<int> get durationStream => durationCtrl.stream;

  @override
  Stream<Song?> get currentSongStream => songCtrl.stream;

  @override
  Stream<PlayerState> get stateStream => const Stream.empty();

  @override
  Stream<int> get positionStream => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeCache implements AudioCache {
  @override
  Future<void> cacheAfterPlay(Song song, String url,
      {Map<String, String>? headers}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test('duration 先到时，时长写进正在装载的新曲而非旧曲', () async {
    final db = InMemoryDatabaseProvider();
    final oldSong = const Song(
      id: 'old', sourceId: 's', title: 'Old', artist: 'A', duration: 200,
    );
    final newSong = const Song(
      id: 'new', sourceId: 's', title: 'New', artist: 'A',
    );
    final player = _RacePlayer()
      ..queue = [newSong]
      ..currentIndex = 0
      ..audibleSong = oldSong;

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      playerProvider.overrideWithValue(player),
      sourceManagerProvider.overrideWithValue(SourceManager()),
      audioCacheProvider.overrideWithValue(_FakeCache()),
    ]);
    addTearDown(container.dispose);
    // 旧曲已落库（真实场景里上一首通常已在 songs 表）。
    await db.songDao.insertSong(oldSong);

    container.read(playerStreamBindingProvider);

    // 模拟旧曲仍在播：currentTrackId/currentSong 都还是旧曲。
    container.read(currentTrackIdProvider.notifier).set(oldSong.globalKey);
    container.read(playerCurrentSongProvider.notifier).set(oldSong);

    // 真实顺序：新曲 duration 先到，currentSong 后到。
    player.durationCtrl.add(240000);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    player.songCtrl.add(newSong);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final oldRow = await db.songDao.getSong(oldSong.id, oldSong.sourceId);
    final newRow = await db.songDao.getSong(newSong.id, newSong.sourceId);
    expect(oldRow?.duration, 200, reason: '旧曲时长不应被改写');
    expect(newRow?.duration, 240, reason: '新曲应拿到真实时长');
  });
}
