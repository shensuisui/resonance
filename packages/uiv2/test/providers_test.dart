/// Provider 层单元测试（lib/src/providers/providers.dart）。
///
/// 测什么：
///   * ThemeModeNotifier：默认 dark / setMode 持久化到 settings / toggleDark；
///   * WifiOnlyNotifier：默认 true / set 持久化；
///   * VolumeNotifier：默认 0.8 / toggleMute 静音并恢复 lastVolume /
///     setVolume 越界 clamp 到 [0,1]；
///   * SearchHistoryNotifier：add 去重移顶 / clear；
///   * LikedNotifier：toggle 写库带元数据快照（getAllFavoriteRecords 里有
///     title/artist），再 toggle 移除；
///   * PlaylistActions：create -> addSong -> removeSong -> rename -> delete
///     全链路（InMemoryDatabaseProvider 的 playlistDao）；
///   * QueueNotifier：append/insertAt/removeAt/move。
///
/// 模拟数据来源：core 的 InMemoryDatabaseProvider（内存 DAO）与手写 _FakePlayer
/// （stateStream/positionStream/durationStream 显式实现为 const Stream.empty()，
/// 其余成员走 noSuchMethod），不使用 mockito。
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/providers/providers.dart';

/// 手写假播放器：显式实现三个流（noSuchMethod 兜底返回 null 会让订阅崩溃），
/// 其余成员一律 noSuchMethod 抛错，确保测试只依赖真实用到的接口。
class _FakePlayer implements Player {
  final List<double> volumeCalls = [];
  final List<PlayMode> modeCalls = [];

  @override
  Stream<PlayerState> get stateStream => const Stream.empty();

  @override
  Stream<int> get positionStream => const Stream.empty();

  @override
  Stream<int> get durationStream => const Stream.empty();

  @override
  set playMode(PlayMode mode) => modeCalls.add(mode);

  @override
  Future<void> setVolume(double volume) async => volumeCalls.add(volume);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '_FakePlayer 未实现 ${invocation.memberName}');
}

void main() {
  late InMemoryDatabaseProvider db;
  late _FakePlayer player;
  late ProviderContainer container;

  /// 等 build() 里 unawaited 的 load() 完成的辅助（微任务排空）
  Future<void> pumpMicrotasks() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    db = InMemoryDatabaseProvider();
    player = _FakePlayer();
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      playerProvider.overrideWithValue(player),
      // songsOf 缺快照时回源需要 SourceManager；快照齐全时只读不查
      sourceManagerProvider.overrideWithValue(SourceManager()),
    ]);
    addTearDown(container.dispose);
  });

  group('ThemeModeNotifier', () {
    test('默认 dark', () {
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    test('setMode 持久化到 settings，load 能恢复', () async {
      await container.read(themeModeProvider.notifier).setMode(ThemeMode.light);
      expect(container.read(themeModeProvider), ThemeMode.light);
      expect(await db.settingsDao.get(ThemeModeNotifier.key), 'light');

      // 新容器（同 db）恢复
      final container2 = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container2.dispose);
      // 首次 read 触发 build（默认 dark）并启动 unawaited 的 load()
      container2.read(themeModeProvider);
      await pumpMicrotasks();
      // load 完成后状态被 settings 里的值覆盖
      expect(container2.read(themeModeProvider), ThemeMode.light);
    });

    test('toggleDark 在明暗之间切换', () async {
      final notifier = container.read(themeModeProvider.notifier);
      await notifier.toggleDark();
      expect(container.read(themeModeProvider), ThemeMode.light);
      await notifier.toggleDark();
      expect(container.read(themeModeProvider), ThemeMode.dark);
    });
  });

  group('WifiOnlyNotifier', () {
    test('默认 true', () {
      expect(container.read(wifiOnlyProvider), isTrue);
    });

    test('set(false) 更新状态并持久化', () async {
      await container.read(wifiOnlyProvider.notifier).set(false);
      expect(container.read(wifiOnlyProvider), isFalse);
      expect(await db.settingsDao.get(WifiOnlyNotifier.key), '0');

      // 新容器恢复为 false
      final container2 = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container2.dispose);
      container2.read(wifiOnlyProvider);
      await pumpMicrotasks();
      expect(container2.read(wifiOnlyProvider), isFalse);
    });
  });

  group('VolumeNotifier', () {
    test('默认 0.8 / lastVolume 0.8 / 未静音', () {
      final state = container.read(volumeProvider);
      expect(state.volume, 0.8);
      expect(state.lastVolume, 0.8);
      expect(state.muted, isFalse);
    });

    test('setVolume 写入播放器并持久化', () async {
      await container.read(volumeProvider.notifier).setVolume(0.5);
      expect(container.read(volumeProvider).volume, 0.5);
      expect(player.volumeCalls, [0.5]);
      expect(await db.settingsDao.get(VolumeNotifier.key), '0.5');
    });

    test('setVolume 越界 clamp 到 [0,1]', () async {
      final notifier = container.read(volumeProvider.notifier);
      await notifier.setVolume(1.5);
      expect(container.read(volumeProvider).volume, 1.0);
      await notifier.setVolume(-0.7);
      final state = container.read(volumeProvider);
      expect(state.volume, 0.0);
      // 静音方向的越界不覆盖 lastVolume（保留 1.0）
      expect(state.lastVolume, 1.0);
      expect(state.muted, isTrue);
    });

    test('toggleMute：静音 -> 恢复 lastVolume', () async {
      final notifier = container.read(volumeProvider.notifier);
      await notifier.setVolume(0.6);
      await notifier.toggleMute();
      expect(container.read(volumeProvider).volume, 0.0);
      expect(await db.settingsDao.get(VolumeNotifier.key), '0');
      await notifier.toggleMute();
      expect(container.read(volumeProvider).volume, 0.6);
      expect(player.volumeCalls, [0.6, 0.0, 0.6]);
    });
  });

  group('SearchHistoryNotifier', () {
    test('默认空，add 持久化为 JSON 数组', () async {
      final notifier = container.read(searchHistoryProvider.notifier);
      expect(container.read(searchHistoryProvider), isEmpty);
      await notifier.add('周杰伦');
      expect(container.read(searchHistoryProvider), ['周杰伦']);
      // settings 里是 JSON 数组格式（与 ui 包互通）
      expect(await db.settingsDao.get(SearchHistoryNotifier.key),
          '["周杰伦"]');
    });

    test('add 去重并把重复项移到顶部', () async {
      final notifier = container.read(searchHistoryProvider.notifier);
      await notifier.add('a');
      await notifier.add('b');
      await notifier.add('c');
      expect(container.read(searchHistoryProvider), ['c', 'b', 'a']);
      await notifier.add('a'); // 重复：移到顶部
      expect(container.read(searchHistoryProvider), ['a', 'c', 'b']);
    });

    test('空白关键字不入历史', () async {
      final notifier = container.read(searchHistoryProvider.notifier);
      await notifier.add('   ');
      expect(container.read(searchHistoryProvider), isEmpty);
    });

    test('clear 清空并持久化', () async {
      final notifier = container.read(searchHistoryProvider.notifier);
      await notifier.add('x');
      await notifier.clear();
      expect(container.read(searchHistoryProvider), isEmpty);
      final raw = await db.settingsDao.get(SearchHistoryNotifier.key);
      expect(raw, '[]');
    });

    test('load 能从 settings 恢复（含坏 JSON 回退为空）', () async {
      await db.settingsDao.set(SearchHistoryNotifier.key, '["p","q"]');
      final container2 = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container2.dispose);
      container2.read(searchHistoryProvider);
      await pumpMicrotasks();
      expect(container2.read(searchHistoryProvider), ['p', 'q']);
    });
  });

  group('LikedNotifier', () {
    Song song(String id, String title, String artist) => Song(
      id: id,
      sourceId: 'demo_catalog',
      title: title,
      artist: artist,
    );

    test('默认空列表', () {
      expect(container.read(likedProvider), isEmpty);
    });

    test('toggle 写库带元数据快照，再 toggle 移除', () async {
      final notifier = container.read(likedProvider.notifier);
      final s = song('midnights#3', 'Anti-Hero', 'Taylor Swift');

      await notifier.toggle(s);
      expect(container.read(likedProvider).length, 1);
      // 验证库里有快照（title/artist 非空）
      final records = await db.favoritesDao.getAllFavoriteRecords();
      expect(records, hasLength(1));
      expect(records.first.songKey, 'demo_catalog:midnights#3');
      expect(records.first.title, 'Anti-Hero');
      expect(records.first.artist, 'Taylor Swift');
      expect(await db.favoritesDao.isFavorite(s.globalKey), isTrue);

      // 再 toggle：移除
      await notifier.toggle(s);
      expect(container.read(likedProvider), isEmpty);
      expect(await db.favoritesDao.isFavorite(s.globalKey), isFalse);
    });

    test('containsKey 按全局键判断', () async {
      final notifier = container.read(likedProvider.notifier);
      final s = song('blonde#7', 'Self Control', 'Frank Ocean');
      expect(notifier.containsKey(s.globalKey), isFalse);
      await notifier.toggle(s);
      expect(notifier.containsKey(s.globalKey), isTrue);
    });

    test('load 按时间新->旧排序', () async {
      final dao = db.favoritesDao;
      await dao.addFavorite('s:old', 1000, title: '旧', artist: 'a');
      await dao.addFavorite('s:new', 2000, title: '新', artist: 'b');
      await container.read(likedProvider.notifier).load();
      final keys = container.read(likedProvider).map((r) => r.songKey);
      expect(keys, ['s:new', 's:old']);
    });
  });

  group('PlaylistActions 全链路', () {
    Song song(String id) => Song(
      id: id,
      sourceId: 'demo_catalog',
      title: 't-$id',
      artist: 'ar',
    );

    test('create -> addSong -> removeSong -> rename -> delete', () async {
      final actions = container.read(playlistActionsProvider);

      // 1. 新建
      final id = await actions.create('我的歌单', description: '测试');
      expect(id, startsWith('up-'));
      final created = await db.playlistDao.getPlaylist(id);
      expect(created, isNotNull);
      expect(created!.name, '我的歌单');
      expect(created.songKeys, isEmpty);

      // 2. 加歌（带快照）
      expect(await actions.addSong(id, song('a1')), isTrue);
      expect(await actions.addSong(id, song('a2')), isTrue);
      // 重复加同一家被拒
      expect(await actions.addSong(id, song('a1')), isFalse);
      var pl = await db.playlistDao.getPlaylist(id);
      expect(pl!.songKeys, ['demo_catalog:a1', 'demo_catalog:a2']);
      expect(pl.songSnapshots['demo_catalog:a1']!.title, 't-a1');

      // 3. 移歌
      expect(await actions.removeSong(id, 'demo_catalog:a1'), isTrue);
      expect(await actions.removeSong(id, 'demo_catalog:a1'), isFalse,
          reason: '已移除的歌再移一次应返回 false');
      pl = await db.playlistDao.getPlaylist(id);
      expect(pl!.songKeys, ['demo_catalog:a2']);
      expect(pl.songSnapshots.containsKey('demo_catalog:a1'), isFalse);

      // 4. 重命名
      await actions.rename(id, '改名后的歌单');
      pl = await db.playlistDao.getPlaylist(id);
      expect(pl!.name, '改名后的歌单');
      // rename 不动歌曲列表
      expect(pl.songKeys, ['demo_catalog:a2']);

      // 5. 删除
      await actions.delete(id);
      expect(await db.playlistDao.getPlaylist(id), isNull);
    });

    test('addSong 对不存在的歌单返回 false', () async {
      final actions = container.read(playlistActionsProvider);
      expect(await actions.addSong('no-such', song('a1')), isFalse);
    });

    test('rename/delete 对不存在的歌单安全无副作用', () async {
      final actions = container.read(playlistActionsProvider);
      await actions.rename('no-such', 'x');
      await actions.delete('no-such');
      expect(await db.playlistDao.getAllPlaylists(), isEmpty);
    });

    test('songsOf 优先用快照', () async {
      final actions = container.read(playlistActionsProvider);
      final id = await actions.create('快照歌单');
      await actions.addSong(id, song('b1'));
      final pl = (await db.playlistDao.getPlaylist(id))!;
      final songs = await actions.songsOf(pl);
      expect(songs.map((s) => s.id), ['b1']);
    });
  });

  group('QueueNotifier', () {
    Song song(String id) => Song(
      id: id, sourceId: 'demo_catalog', title: id, artist: 'ar',
    );

    test('append 追加到队尾', () {
      final notifier = container.read(queueProvider.notifier);
      notifier.append(song('a'));
      notifier.append(song('b'));
      expect(container.read(queueProvider).songs.map((s) => s.id), ['a', 'b']);
    });

    test('insertAt 插入并 clamp 越界下标', () {
      final notifier = container.read(queueProvider.notifier);
      notifier.setSongs([song('a'), song('b')]);
      notifier.insertAt(1, song('c'));
      expect(container.read(queueProvider).songs.map((s) => s.id), ['a', 'c', 'b']);
      // 越界：clamp 到末尾
      notifier.insertAt(99, song('d'));
      expect(container.read(queueProvider).songs.map((s) => s.id),
          ['a', 'c', 'b', 'd']);
    });

    test('removeAt 移除并返回被移除歌曲；越界返回 null', () {
      final notifier = container.read(queueProvider.notifier);
      notifier.setSongs([song('a'), song('b'), song('c')]);
      final removed = notifier.removeAt(1);
      expect(removed!.id, 'b');
      expect(container.read(queueProvider).songs.map((s) => s.id), ['a', 'c']);
      expect(notifier.removeAt(99), isNull);
      expect(notifier.removeAt(-1), isNull);
    });

    test('move 移动到新下标（含 clamp）', () {
      final notifier = container.read(queueProvider.notifier);
      notifier.setSongs([song('a'), song('b'), song('c'), song('d')]);
      notifier.move(0, 2); // a 移到下标 2
      expect(container.read(queueProvider).songs.map((s) => s.id),
          ['b', 'c', 'a', 'd']);
      notifier.move(3, 99); // clamp 到末尾
      expect(container.read(queueProvider).songs.map((s) => s.id),
          ['b', 'c', 'a', 'd']);
      expect(container.read(queueProvider).songs.last.id, 'd');
      // 非法 from 无副作用
      notifier.move(99, 0);
      expect(container.read(queueProvider).songs.length, 4);
    });

    test('containsKey 按全局键判断', () {
      final notifier = container.read(queueProvider.notifier);
      notifier.setSongs([song('a')]);
      expect(notifier.containsKey('demo_catalog:a'), isTrue);
      expect(notifier.containsKey('demo_catalog:zz'), isFalse);
    });
  });

  group('其余轻量 Notifier', () {
    test('currentTrackIdProvider 默认 null，可 set', () {
      expect(container.read(currentTrackIdProvider), isNull);
      container.read(currentTrackIdProvider.notifier).set('demo_catalog:a');
      expect(container.read(currentTrackIdProvider), 'demo_catalog:a');
    });

    test('isPlayingProvider 默认 false', () {
      expect(container.read(isPlayingProvider), isFalse);
    });

    test('positionProvider/durationProvider 默认 0', () {
      expect(container.read(positionProvider), Duration.zero);
      expect(container.read(durationProvider), Duration.zero);
    });

    test('nowPlayingProvider open/close/toggle', () {
      final notifier = container.read(nowPlayingProvider.notifier);
      expect(container.read(nowPlayingProvider), isFalse);
      notifier.open();
      expect(container.read(nowPlayingProvider), isTrue);
      notifier.toggle();
      expect(container.read(nowPlayingProvider), isFalse);
      notifier.close();
      expect(container.read(nowPlayingProvider), isFalse);
    });
  });
}
