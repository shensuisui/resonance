import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('Song', () {
    test('creates with required fields', () {
      final song = Song(id: '1', sourceId: 'test', title: 'Test Song', artist: 'Test Artist');
      expect(song.id, '1');
      expect(song.sourceId, 'test');
      expect(song.globalKey, 'test:1');
    });

    test('equality based on id and sourceId', () {
      final a = Song(id: '1', sourceId: 'test', title: 'A', artist: 'A');
      final b = Song(id: '1', sourceId: 'test', title: 'B', artist: 'B');
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('inequality with different sourceId', () {
      final a = Song(id: '1', sourceId: 'test', title: 'A', artist: 'A');
      final b = Song(id: '1', sourceId: 'other', title: 'A', artist: 'A');
      expect(a == b, isFalse);
    });

    test('copyWith creates new instance with updated fields', () {
      final original = Song(id: '1', sourceId: 'test', title: 'Original', artist: 'A');
      final updated = original.copyWith(title: 'Updated');
      expect(original.title, 'Original');
      expect(updated.title, 'Updated');
      expect(updated.id, original.id);
    });

    test('globalKey format', () {
      final song = Song(id: '123', sourceId: 'netease', title: 'T', artist: 'A');
      expect(song.globalKey, 'netease:123');
    });
  });

  group('Album', () {
    test('creates album with required fields', () {
      final album = Album(id: '1', sourceId: 'test', title: 'Album', artist: 'A');
      expect(album.title, 'Album');
      expect(album.songs, isEmpty);
    });
  });

  group('Artist', () {
    test('creates artist with required fields', () {
      final artist = Artist(id: '1', sourceId: 'test', name: 'Artist Name');
      expect(artist.name, 'Artist Name');
    });
  });

  group('Lyrics', () {
    test('creates lyrics with lines', () {
      final lyrics = Lyrics(
        songId: '1',
        sourceId: 'test',
        lines: [
          LyricLine(time: Duration(seconds: 0), text: 'start'),
          LyricLine(time: Duration(seconds: 10), text: 'verse'),
        ],
      );
      expect(lyrics.lines.length, 2);
      expect(lyrics.lines[0].text, 'start');
      expect(lyrics.isLrc, isTrue);
    });
  });

  group('Playlist', () {
    test('creates playlist with required fields', () {
      final now = DateTime.now();
      final playlist = Playlist(
        id: 'uuid-1',
        name: 'My Playlist',
        createdTime: now,
        modifiedTime: now,
      );
      expect(playlist.name, 'My Playlist');
      expect(playlist.songKeys, isEmpty);
    });

    test('songKeys are stored', () {
      final now = DateTime.now();
      final playlist = Playlist(
        id: 'uuid-1',
        name: 'Favorites',
        songKeys: ['netease:1', 'qq:2'],
        createdTime: now,
        modifiedTime: now,
      );
      expect(playlist.songKeys.length, 2);
    });
  });

  group('SearchResult', () {
    test('creates search result', () {
      final result = SearchResult(
        songs: [
          Song(id: '1', sourceId: 'test', title: 'T', artist: 'A'),
        ],
        sourceId: 'test',
        hasMore: true,
        nextPage: 2,
      );
      expect(result.songs.length, 1);
      expect(result.hasMore, isTrue);
      expect(result.nextPage, 2);
    });
  });

  group('SourceInfo', () {
    test('creates source info', () {
      final info = SourceInfo(id: 'test', name: 'Test', type: SourceType.local);
      expect(info.id, 'test');
      expect(info.type, SourceType.local);
      expect(info.enabled, isTrue);
    });
  });

  group('Enums', () {
    test('PlayMode has all values', () {
      expect(PlayMode.values.length, 4);
      expect(PlayMode.listLoop, isA<PlayMode>());
    });

    test('PlayerState has all values', () {
      expect(PlayerState.values.length, 6);
      expect(PlayerState.idle, isA<PlayerState>());
    });

    test('SourceType has all values', () {
      expect(SourceType.values.length, 3);
      expect(SourceType.local, isA<SourceType>());
    });
  });
}