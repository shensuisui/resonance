/// SourceManager 聚合搜索测试
///
/// 验证：
/// - searchAll 并行搜索多个源
/// - 只搜索已启用的源
/// - 禁用的源不参与搜索
/// - eagerError: false 某源失败不影响其他源

import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('SourceManager 聚合搜索', () {
    late SourceManager manager;

    setUp(() {
      manager = SourceManager();
    });

    test('searchAll 并行搜索多个已启用源', () async {
      // 注册两个源
      manager.registerSource(_StubSource('src_a', [
        Song(id: 'a1', sourceId: 'src_a', title: '稻香', artist: '周杰伦'),
        Song(id: 'a2', sourceId: 'src_a', title: '晴天', artist: '周杰伦'),
      ]));
      manager.registerSource(_StubSource('src_b', [
        Song(id: 'b1', sourceId: 'src_b', title: '孤勇者', artist: '陈奕迅'),
      ]));
      manager.setSourceEnabled('src_a', true);
      manager.setSourceEnabled('src_b', true);

      final results = await manager.searchAll(keyword: '周杰伦');

      // 两个源都返回结果
      expect(results.length, 2);

      // 汇总歌曲数（'周杰伦' 匹配 src_a 的 2 首，src_b 的孤勇者不匹配）
      final allSongs = results.expand((r) => r.songs).toList();
      expect(allSongs.length, 2);
    });

    test('禁用的源不参与搜索', () async {
      manager.registerSource(_StubSource('src_a', [
        Song(id: 'a1', sourceId: 'src_a', title: '歌A', artist: '手'),
      ]));
      manager.registerSource(_StubSource('src_b', [
        Song(id: 'b1', sourceId: 'src_b', title: '歌B', artist: '手'),
      ]));
      manager.setSourceEnabled('src_a', true);
      manager.setSourceEnabled('src_b', false); // 禁用

      final results = await manager.searchAll(keyword: '歌');

      // 只有 src_a 返回
      expect(results.length, 1);
      expect(results.first.sourceId, 'src_a');
    });

    test('全部禁用时返回空列表', () async {
      manager.registerSource(_StubSource('src_a', [
        Song(id: 'a1', sourceId: 'src_a', title: '歌', artist: '手'),
      ]));
      manager.setSourceEnabled('src_a', false);

      final results = await manager.searchAll(keyword: '歌');
      expect(results, isEmpty);
    });

    test('某源抛异常不影响其他源 (eagerError: false)', () async {
      manager.registerSource(_StubSource('good', [
        Song(id: 'g1', sourceId: 'good', title: '好歌', artist: '手'),
      ]));
      manager.registerSource(_ErrorSource('bad'));
      manager.setSourceEnabled('good', true);
      manager.setSourceEnabled('bad', true);

      final results = await manager.searchAll(keyword: '好');

      // bad 源抛异常，但 good 源正常返回
      // Future.wait with eagerError: false 会让失败的 Future 返回其错误值
      // 结果数量取决于实现——至少 good 源的结果应存在
      final goodResults = results.where((r) => r.sourceId == 'good');
      expect(goodResults, isNotEmpty);
    });

    test('getSongDetail 委托到对应源', () async {
      manager.registerSource(_StubSource('src_a', [
        Song(id: 'a1', sourceId: 'src_a', title: '歌', artist: '手'),
      ]));
      manager.setSourceEnabled('src_a', true);

      final song = await manager.getSongDetail('src_a', 'a1');
      expect(song.title, '歌');
    });

    test('getSongDetail 不存在的源抛异常', () async {
      expect(
        () => manager.getSongDetail('nonexistent', '1'),
        throwsException,
      );
    });

    test('unregisterSource 移除源', () async {
      manager.registerSource(_StubSource('src_a', [
        Song(id: 'a1', sourceId: 'src_a', title: '歌', artist: '手'),
      ]));
      manager.setSourceEnabled('src_a', true);
      expect(manager.getAllSources().length, 1);

      manager.unregisterSource('src_a');
      expect(manager.getAllSources(), isEmpty);
      expect(manager.getSource('src_a'), isNull);
    });
  });
}

/// 测试用源——返回预设歌曲列表
class _StubSource extends MusicSource {
  final String _id;
  final List<Song> _songs;

  _StubSource(this._id, this._songs);

  @override
  SourceInfo get sourceInfo => SourceInfo(
        id: _id,
        name: 'Source $_id',
        type: SourceType.local,
      );

  @override
  Future<SearchResult> search({
    String? keyword,
    int page = 1,
    int pageSize = 20,
  }) async {
    final kw = (keyword ?? '').toLowerCase();
    final matched = _songs
        .where((s) =>
            s.title.toLowerCase().contains(kw) ||
            s.artist.toLowerCase().contains(kw))
        .toList();
    return SearchResult(songs: matched, sourceId: _id);
  }

  @override
  Future<Song> getSongDetail(String id) async {
    return _songs.firstWhere((s) => s.id == id);
  }

  @override
  Future<String> getSongUrl(String id) async => 'http://example.com/$id';

  @override
  Future<Lyrics?> getLyrics(String id) async => null;

  @override
  Future<Album?> getAlbum(String id) async => null;

  @override
  Future<Artist?> getArtist(String id) async => null;

  @override
  Future<Playlist?> getPlaylist(String id) async => null;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}
}

/// 测试用源——搜索时抛异常
class _ErrorSource extends MusicSource {
  final String _id;

  _ErrorSource(this._id);

  @override
  SourceInfo get sourceInfo => SourceInfo(
        id: _id,
        name: 'Error Source',
        type: SourceType.local,
      );

  @override
  Future<SearchResult> search({
    String? keyword,
    int page = 1,
    int pageSize = 20,
  }) async {
    throw Exception('Source error');
  }

  @override
  Future<Song> getSongDetail(String id) async => throw Exception();

  @override
  Future<String> getSongUrl(String id) async => throw Exception();

  @override
  Future<Lyrics?> getLyrics(String id) async => null;

  @override
  Future<Album?> getAlbum(String id) async => null;

  @override
  Future<Artist?> getArtist(String id) async => null;

  @override
  Future<Playlist?> getPlaylist(String id) async => null;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}
}
