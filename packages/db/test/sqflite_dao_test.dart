/// SQLite DAO 完整测试
///
/// 使用 sqflite_common_ffi 的内存数据库（inMemoryDatabasePath），
/// 不依赖真实文件系统，跨平台运行。
///
/// 覆盖：
/// - SongDao CRUD + 搜索
/// - PlaylistDao CRUD + 关联表保序
/// - RecentPlaysDao 去重/移顶/清理
/// - FavoritesDao 增删查
/// - SettingsDao key-value
/// - RecentPlaysService 业务逻辑

import 'dart:io';
import 'package:core/core.dart';
import 'package:db/db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 测试用数据库助手工厂
///
/// 使用 sqflite_common_ffi 的内存数据库路径，
/// 每个测试独立实例，互不干扰。
DatabaseHelper _newInMemoryHelper() {
  // FFI 初始化（桌面端测试环境）
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  // inMemoryDatabasePath 是 sqflite_common_ffi 提供的特殊路径
  return DatabaseHelper(customDbPath: inMemoryDatabasePath);
}

void main() {
  late SqfliteDatabaseProvider provider;

  setUp(() async {
    provider = SqfliteDatabaseProvider.withHelper(_newInMemoryHelper());
    await provider.initialize();
  });

  tearDown(() async {
    await provider.close();
  });

  // ==================== SongDao ====================
  group('SongDao', () {
    test('插入并按 (id, sourceId) 查询', () async {
      final song = Song(
        id: '001',
        sourceId: 'test_source',
        title: '稻香',
        artist: '周杰伦',
        album: '魔杰座',
        duration: 223,
        coverUrl: 'https://example.com/cover.jpg',
        playUrl: 'https://example.com/play.mp3',
      );

      await provider.songDao.insertSong(song);
      final result = await provider.songDao.getSong('001', 'test_source');

      expect(result, isNotNull);
      expect(result!.title, '稻香');
      expect(result.artist, '周杰伦');
      expect(result.album, '魔杰座');
      expect(result.duration, 223);
      expect(result.coverUrl, 'https://example.com/cover.jpg');
      expect(result.playUrl, 'https://example.com/play.mp3');
    });

    test('不同源同 id 互不干扰', () async {
      final songA = Song(id: '001', sourceId: 'source_a', title: 'A', artist: 'ArtistA');
      final songB = Song(id: '001', sourceId: 'source_b', title: 'B', artist: 'ArtistB');

      await provider.songDao.insertSong(songA);
      await provider.songDao.insertSong(songB);

      final a = await provider.songDao.getSong('001', 'source_a');
      final b = await provider.songDao.getSong('001', 'source_b');

      expect(a!.title, 'A');
      expect(b!.title, 'B');
    });

    test('更新歌曲字段', () async {
      final song = Song(id: '001', sourceId: 'test', title: '原标题', artist: '歌手');
      await provider.songDao.insertSong(song);

      await provider.songDao.updateSong(song.copyWith(
        title: '新标题',
        playUrl: 'https://example.com/new.mp3',
      ));

      final result = await provider.songDao.getSong('001', 'test');
      expect(result!.title, '新标题');
      expect(result.playUrl, 'https://example.com/new.mp3');
    });

    test('删除歌曲', () async {
      final song = Song(id: '001', sourceId: 'test', title: '歌', artist: '手');
      await provider.songDao.insertSong(song);
      await provider.songDao.deleteSong('001', 'test');

      final result = await provider.songDao.getSong('001', 'test');
      expect(result, isNull);
    });

    test('按关键词搜索标题和歌手', () async {
      await provider.songDao.insertSong(Song(id: '1', sourceId: 's', title: '稻香', artist: '周杰伦'));
      await provider.songDao.insertSong(Song(id: '2', sourceId: 's', title: '晴天', artist: '周杰伦'));
      await provider.songDao.insertSong(Song(id: '3', sourceId: 's', title: '孤勇者', artist: '陈奕迅'));

      final byTitle = await provider.songDao.searchSongs('稻香');
      expect(byTitle.length, 1);
      expect(byTitle.first.title, '稻香');

      final byArtist = await provider.songDao.searchSongs('周杰伦');
      expect(byArtist.length, 2);

      final byPartial = await provider.songDao.searchSongs('孤');
      expect(byPartial.length, 1);
      expect(byPartial.first.title, '孤勇者');
    });

    test('extra 字段正确序列化和反序列化', () async {
      final song = Song(
        id: '001',
        sourceId: 'test',
        title: '歌',
        artist: '手',
        extra: {'quality': '320k', 'bitrate': 320, 'tags': ['pop', 'rock']},
      );
      await provider.songDao.insertSong(song);
      final result = await provider.songDao.getSong('001', 'test');

      expect(result!.extra['quality'], '320k');
      expect(result.extra['bitrate'], 320);
      expect(result.extra['tags'], ['pop', 'rock']);
    });
  });

  // ==================== PlaylistDao ====================
  group('PlaylistDao', () {
    test('插入歌单并获取（含 songKeys 保序）', () async {
      final playlist = Playlist(
        id: 'pl-001',
        name: '我的歌单',
        songKeys: ['s1:001', 's1:002', 's2:003'],
        createdTime: DateTime(2026, 1, 1),
        modifiedTime: DateTime(2026, 1, 2),
      );

      await provider.playlistDao.insertPlaylist(playlist);
      final result = await provider.playlistDao.getPlaylist('pl-001');

      expect(result, isNotNull);
      expect(result!.name, '我的歌单');
      expect(result.songKeys.length, 3);
      // 验证顺序
      expect(result.songKeys[0], 's1:001');
      expect(result.songKeys[1], 's1:002');
      expect(result.songKeys[2], 's2:003');
    });

    test('获取所有歌单（按修改时间倒序）', () async {
      await provider.playlistDao.insertPlaylist(Playlist(
        id: 'pl-1', name: '旧歌单', songKeys: [],
        createdTime: DateTime(2026, 1, 1), modifiedTime: DateTime(2026, 1, 1),
      ));
      await provider.playlistDao.insertPlaylist(Playlist(
        id: 'pl-2', name: '新歌单', songKeys: [],
        createdTime: DateTime(2026, 1, 1), modifiedTime: DateTime(2026, 1, 5),
      ));

      final all = await provider.playlistDao.getAllPlaylists();
      expect(all.length, 2);
      expect(all.first.name, '新歌单'); // modified_time DESC
    });

    test('更新歌单（替换 songKeys）', () async {
      final playlist = Playlist(
        id: 'pl-001', name: '歌单', songKeys: ['a:1', 'a:2'],
        createdTime: DateTime(2026, 1, 1), modifiedTime: DateTime(2026, 1, 1),
      );
      await provider.playlistDao.insertPlaylist(playlist);

      await provider.playlistDao.updatePlaylist(playlist.copyWith(
        name: '改名歌单',
        songKeys: ['b:1', 'b:2', 'b:3'],
        modifiedTime: DateTime(2026, 1, 10),
      ));

      final result = await provider.playlistDao.getPlaylist('pl-001');
      expect(result!.name, '改名歌单');
      expect(result.songKeys.length, 3);
      expect(result.songKeys.first, 'b:1');
      expect(result.songKeys.last, 'b:3');
    });

    test('删除歌单（关联表级联删除）', () async {
      final playlist = Playlist(
        id: 'pl-001', name: '歌单', songKeys: ['a:1', 'a:2'],
        createdTime: DateTime(2026, 1, 1), modifiedTime: DateTime(2026, 1, 1),
      );
      await provider.playlistDao.insertPlaylist(playlist);
      await provider.playlistDao.deletePlaylist('pl-001');

      final result = await provider.playlistDao.getPlaylist('pl-001');
      expect(result, isNull);
    });
  });

  // ==================== RecentPlaysDao ====================
  group('RecentPlaysDao', () {
    test('插入/更新（去重 + 移顶）', () async {
      await provider.recentPlaysDao.insertOrUpdateRecentPlay('s:1', 1000);
      await provider.recentPlaysDao.insertOrUpdateRecentPlay('s:2', 2000);
      await provider.recentPlaysDao.insertOrUpdateRecentPlay('s:3', 3000);

      // s:1 重新播放，时间最新
      await provider.recentPlaysDao.insertOrUpdateRecentPlay('s:1', 4000);

      final keys = await provider.recentPlaysDao.getRecentPlayKeys();
      expect(keys.first, 's:1'); // 最新播放的在最前
      expect(keys.length, 3);
    });

    test('cleanOldest 超出上限删除最旧', () async {
      for (int i = 0; i < 10; i++) {
        await provider.recentPlaysDao.insertOrUpdateRecentPlay('s:$i', i * 1000);
      }

      await provider.recentPlaysDao.cleanOldest(5);
      final keys = await provider.recentPlaysDao.getRecentPlayKeys();
      expect(keys.length, 5);
      // 保留的是最新的 5 个（s:5 ~ s:9）
      expect(keys.first, 's:9');
      expect(keys.last, 's:5');
    });
  });

  // ==================== FavoritesDao ====================
  group('FavoritesDao', () {
    test('添加/检查/移除收藏', () async {
      await provider.favoritesDao.addFavorite('s:001', 1000);
      expect(await provider.favoritesDao.isFavorite('s:001'), isTrue);
      expect(await provider.favoritesDao.isFavorite('s:002'), isFalse);

      await provider.favoritesDao.removeFavorite('s:001');
      expect(await provider.favoritesDao.isFavorite('s:001'), isFalse);
    });

    test('获取所有收藏键', () async {
      await provider.favoritesDao.addFavorite('s:001', 1000);
      await provider.favoritesDao.addFavorite('s:002', 2000);
      await provider.favoritesDao.addFavorite('s:003', 3000);

      final keys = await provider.favoritesDao.getAllFavoriteKeys();
      expect(keys.length, 3);
      expect(keys, containsAll(['s:001', 's:002', 's:003']));
    });
  });

  // ==================== SettingsDao ====================
  group('SettingsDao', () {
    test('设置和获取值', () async {
      await provider.settingsDao.set('theme_mode', 'dark');
      await provider.settingsDao.set('scan_dir', '/music');

      expect(await provider.settingsDao.get('theme_mode'), 'dark');
      expect(await provider.settingsDao.get('scan_dir'), '/music');
      expect(await provider.settingsDao.get('nonexistent'), isNull);
    });

    test('获取所有设置', () async {
      await provider.settingsDao.set('theme_mode', 'light');
      await provider.settingsDao.set('scan_dir', '/music');

      final all = await provider.settingsDao.getAll();
      expect(all.length, 2);
      expect(all['theme_mode'], 'light');
      expect(all['scan_dir'], '/music');
    });

    test('更新已存在的键', () async {
      await provider.settingsDao.set('theme_mode', 'light');
      await provider.settingsDao.set('theme_mode', 'dark');

      expect(await provider.settingsDao.get('theme_mode'), 'dark');
      final all = await provider.settingsDao.getAll();
      expect(all.length, 1);
    });

    test('删除设置', () async {
      await provider.settingsDao.set('temp', 'value');
      await provider.settingsDao.delete('temp');
      expect(await provider.settingsDao.get('temp'), isNull);
    });
  });

  // ==================== RecentPlaysService ====================
  group('RecentPlaysService', () {
    late RecentPlaysService service;

    setUp(() {
      service = RecentPlaysService(provider.recentPlaysDao);
    });

    test('recordPlay 记录播放并去重移顶', () async {
      final song1 = Song(id: '1', sourceId: 's', title: '歌1', artist: '手1');
      final song2 = Song(id: '2', sourceId: 's', title: '歌2', artist: '手2');

      await service.recordPlay(song1);
      await Future.delayed(const Duration(milliseconds: 10));
      await service.recordPlay(song2);
      await Future.delayed(const Duration(milliseconds: 10));
      await service.recordPlay(song1); // 重复播放，移至顶部

      final keys = await service.getRecentSongKeys();
      expect(keys.first, song1.globalKey); // 最新播放
      expect(keys.length, 2);
    });

    test('超出 500 上限自动清理', () async {
      for (int i = 0; i < 510; i++) {
        await service.recordPlay(Song(
          id: '$i', sourceId: 's', title: '歌$i', artist: '手',
        ));
      }

      final keys = await service.getRecentSongKeys();
      expect(keys.length, lessThanOrEqualTo(500));
    });

    test('清空最近播放', () async {
      await service.recordPlay(Song(id: '1', sourceId: 's', title: '歌', artist: '手'));
      await service.clear();

      final keys = await service.getRecentSongKeys();
      expect(keys, isEmpty);
    });
  });
}
