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
      await source.addFavorite('test:1', 'test', '1');
      expect(await source.isFavorite('test:1'), isTrue);
    });

    test('remove favorite', () async {
      await source.addFavorite('test:1', 'test', '1');
      await source.removeFavorite('test:1');
      expect(await source.isFavorite('test:1'), isFalse);
    });

    test('search returns empty when no favorites', () async {
      final result = await source.search(keyword: 'anything');
      expect(result.songs, isEmpty);
    });
  });
}