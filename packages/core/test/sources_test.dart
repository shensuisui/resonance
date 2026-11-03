import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('LocalCustomSource', () {
    late InMemoryDatabaseProvider db;
    late LocalCustomSource source;

    setUp(() {
      db = InMemoryDatabaseProvider();
      source = LocalCustomSource(db.songDao);
    });

    test('add and search custom song', () async {
      final song = Song(id: '1', sourceId: 'local_custom', title: 'My Song', artist: 'Me');
      await source.addCustomSong(song);

      final result = await source.search(keyword: 'My');
      expect(result.songs.length, 1);
      expect(result.songs.first.title, 'My Song');
    });

    test('remove custom song', () async {
      await source.addCustomSong(Song(id: '1', sourceId: 'local_custom', title: 'T', artist: 'A'));
      await source.removeCustomSong('1');
      final result = await source.search(keyword: 'T');
      expect(result.songs, isEmpty);
    });

    test('getSongDetail returns song', () async {
      await source.addCustomSong(Song(id: '1', sourceId: 'local_custom', title: 'T', artist: 'A'));
      final song = await source.getSongDetail('1');
      expect(song.title, 'T');
    });

    test('getSongDetail throws on not found', () {
      expect(() => source.getSongDetail('not-found'), throwsA(anything));
    });

    test('search returns empty for no match', () async {
      await source.addCustomSong(Song(id: '1', sourceId: 'local_custom', title: 'T', artist: 'A'));
      final result = await source.search(keyword: 'zzz');
      expect(result.songs, isEmpty);
    });
  });

  group('FavoriteSource', () {
    late InMemoryDatabaseProvider db;
    late SourceManager sourceManager;
    late FavoriteSource source;
    late LocalScanSource scanSource;

    setUp(() {
      db = InMemoryDatabaseProvider();
      sourceManager = SourceManager();
      source = FavoriteSource(db.favoritesDao, sourceManager);

      // 注册一个测试源
      scanSource = LocalScanSource(db.songDao);
      sourceManager.registerSource(scanSource);
    });

    test('add and check favorite', () async {
      await source.addFavorite(Song(
        id: '1', sourceId: 'test', title: '晴天', artist: '周杰伦',
      ));
      expect(await source.isFavorite('test:1'), isTrue);
    });

    test('save favorite with snapshot', () async {
      // 快照是「我最喜欢」列表显示名字的根因修复
      await source.addFavorite(Song(
        id: '1', sourceId: 'test', title: '晴天', artist: '周杰伦',
        coverUrl: 'http://c/1.jpg',
      ));
      final songs = await source.getFavoriteSongs();
      expect(songs.length, 1);
      expect(songs.first.title, '晴天');
      expect(songs.first.artist, '周杰伦');
      expect(songs.first.coverUrl, 'http://c/1.jpg');
    });

    test('remove favorite', () async {
      await source.addFavorite(Song(
        id: '1', sourceId: 'test', title: '晴天', artist: '周杰伦',
      ));
      await source.removeFavorite('test:1');
      expect(await source.isFavorite('test:1'), isFalse);
    });

    test('search returns empty when no favorites', () async {
      final result = await source.search(keyword: 'anything');
      expect(result.songs, isEmpty);
    });

    // —— 搜索性能回归（用户报：「我最喜欢」这个本地源比所有远端源都慢、排在最后）——
    // 旧实现拿收藏 key 逐条 `getSongDetail` **串行**回源，收藏越多越慢；
    // 而收藏时其实已经存了 title/artist/coverUrl 快照。下面把「有快照就不许回源」钉死。

    test('搜索走快照：有快照时一次源都不回', () async {
      await source.addFavorite(Song(
        id: '1', sourceId: 'test', title: '晴天', artist: '周杰伦',
      ));
      await source.addFavorite(Song(
        id: '2', sourceId: 'test', title: '稻香', artist: '周杰伦',
      ));
      await source.addFavorite(Song(
        id: '3', sourceId: 'test', title: '小半', artist: '陈粒',
      ));

      final counting = _CountingManager();
      final s = FavoriteSource(db.favoritesDao, counting);
      final r = await s.search(keyword: '周杰伦');

      expect(r.songs.length, 2);
      expect(r.songs.map((x) => x.title).toSet(), {'晴天', '稻香'});
      expect(counting.detailCalls, 0,
          reason: '有快照就必须本地匹配 —— 回源一次就是一条串行网络请求');
    });

    test('快照带封面：不回源也能给出封面', () async {
      await source.addFavorite(Song(
        id: '9',
        sourceId: 'test',
        title: '晴天',
        artist: '周杰伦',
        coverUrl: 'http://c/9.jpg',
      ));
      final counting = _CountingManager();
      final s = FavoriteSource(db.favoritesDao, counting);
      final r = await s.search(keyword: '晴天');
      expect(r.songs.single.coverUrl, 'http://c/9.jpg');
      expect(counting.detailCalls, 0);
    });

    test('历史记录（无快照）才回源补齐', () async {
      // 直接写 DAO：模拟「快照功能之前」写入的收藏（title 为 null）
      await db.favoritesDao.addFavorite('test:legacy', 1);
      final counting = _CountingManager();
      final s = FavoriteSource(db.favoritesDao, counting);

      final r = await s.search(keyword: '周杰伦');
      expect(counting.detailCalls, 1, reason: '只有无快照的那条需要回源');
      expect(r.songs.length, 1);
    });
  });
}

/// 数 `getSongDetail` 被调用了几次：用来证明「有快照就不回源」
class _CountingManager extends SourceManager {
  /// 回源次数
  int detailCalls = 0;

  @override
  Future<Song> getSongDetail(String sourceId, String songId) async {
    detailCalls++;
    return Song(
      id: songId,
      sourceId: sourceId,
      title: '晴天',
      artist: '周杰伦',
    );
  }
}