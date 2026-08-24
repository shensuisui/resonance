import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('Song', () {
    test('creates with required fields', () {
      final song = Song(id: '1', sourceId: 'test', title: 'Test', artist: 'A');
      expect(song.title, 'Test');
    });

    test('globalKey format', () {
      final song = Song(id: '123', sourceId: 'netease', title: 'T', artist: 'A');
      expect(song.globalKey, 'netease:123');
    });
  });

  group('SourceManager', () {
    test('register and get sources', () {
      final manager = SourceManager();
      expect(manager.getAllSources(), isEmpty);

      // 使用匿名实现进行测试
      final source = _TestSource();
      manager.registerSource(source);
      expect(manager.getAllSources().length, 1);
      expect(manager.isSourceEnabled('test'), isTrue);
    });

    test('enable/disable sources', () {
      final manager = SourceManager();
      manager.registerSource(_TestSource());
      manager.setSourceEnabled('test', false);
      expect(manager.isSourceEnabled('test'), isFalse);
      expect(manager.getEnabledSources(), isEmpty);
    });
  });
}

class _TestSource extends MusicSource {
  @override
  SourceInfo get sourceInfo => const SourceInfo(
    id: 'test', name: 'Test', type: SourceType.local,
  );

  @override
  Future<SearchResult> search({String? keyword, int page = 1, int pageSize = 20}) async {
    return SearchResult(songs: [], sourceId: 'test');
  }

  @override
  Future<Song> getSongDetail(String id) async {
    throw UnimplementedError();
  }

  @override
  Future<String> getSongUrl(String id) async {
    throw UnimplementedError();
  }

  @override
  Future<Lyrics?> getLyrics(String id) async {
    return null;
  }

  @override
  Future<Album?> getAlbum(String id) async {
    return null;
  }

  @override
  Future<Artist?> getArtist(String id) async {
    return null;
  }

  @override
  Future<Playlist?> getPlaylist(String id) async {
    return null;
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}
}