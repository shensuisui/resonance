/// 当前曲目对象回归测试（真机：播放条标题显示成 "2"）
///
/// 现场：A（歌曲宝 id=2 的《素颜》）正常播放，点一首播不出来的 B 后，
/// 队列被替换成 B 所在的搜索结果 —— 在播的 A 已不在新队列里。
/// 旧实现只留了 id，UI 拿 id 去解析时 resolver 先给「标题 = id」的占位，
/// 于是播放条标题显示成 "2"（封面却靠缓存补上了，所以是"真封面 + 2"）。
///
/// 修法：播放器广播当前曲目时把**完整对象**留进 playerCurrentSongProvider，
/// currentSongProvider 优先用它。这里钉住这条行为。
///
/// 模拟数据：最小假源（只为让 resolver 能找到源）+ core 的内存数据库。
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/providers/providers.dart';

/// 最小假源：resolver 找不到源时会直接返回 null，这里保证源存在
class _StubSource extends MusicSource {
  @override
  SourceInfo get sourceInfo =>
      SourceInfo(id: 'gequbao', name: '歌曲宝', type: SourceType.rule);

  @override
  Future<SearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 20,
  }) async =>
      SearchResult(songs: const <Song>[], sourceId: 'gequbao');

  @override
  Future<Song> getSongDetail(String id) async =>
      Song(id: id, sourceId: 'gequbao', title: '标题', artist: '歌手');

  @override
  Future<String> getSongUrl(String id) async => 'http://audio/' + id + '.mp3';

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

void main() {
  late InMemoryDatabaseProvider db;
  late ProviderContainer container;

  /// 正在播放的 A（歌曲宝 id=2 → 素颜）
  const playing = Song(
      id: '2', sourceId: 'gequbao', title: '素颜', artist: '许嵩&何曼婷');

  /// 新队列里的另一首（队列被换成 B 所在列表后，A 不在其中）
  const other = Song(id: '4190', sourceId: 'gequbao', title: '稻香', artist: '周杰伦');

  setUp(() async {
    db = InMemoryDatabaseProvider();
    await db.initialize();
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sourceManagerProvider.overrideWithValue(SourceManager()..registerSource(_StubSource())),
    ]);
  });

  tearDown(() => container.dispose());

  test('在播曲目不在队列里时，标题仍是真实标题而不是 id 片段', () {
    container.read(currentTrackIdProvider.notifier).set(playing.globalKey);
    container.read(playerCurrentSongProvider.notifier).set(playing);
    container.read(queueProvider.notifier).set(const [other]);

    final cur = container.read(currentSongProvider);
    expect(cur?.title, '素颜', reason: '不能用「标题=id」的占位覆盖真实标题');
    expect(cur?.artist, '许嵩&何曼婷');
  });

  test('没有播放器对象时退回队列查找（旧行为不变）', () {
    container.read(currentTrackIdProvider.notifier).set(other.globalKey);
    container.read(queueProvider.notifier).set(const [other]);

    expect(container.read(currentSongProvider)?.title, '稻香');
  });
}
