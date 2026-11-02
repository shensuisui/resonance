/// SongMetadataService.enrich 的回归测试
///
/// 背景：规则源详情接口一次就同时给出播放地址与封面/歌手/时长，
/// 播放器解析地址时会走 getPlayable（那一趟已经把封面拿回来了）。
/// 如果 enrich 不认这份详情、也不看库里已有的行，就会为了封面再请求一次
/// 同一个详情接口（实测日志里同一 id 出现两次「歌曲详情 请求」）。
///
/// 这里锁定三条：
///   1. 详情已在手上（detail 参数）→ 不再请求，但要把封面落库；
///   2. 库里已有封面/时长      → 不再请求；
///   3. 真的什么都没有        → 才回源请求一次（兜底路径必须保留）。
///
/// 模拟数据：手写计数假源（只关心 getSongDetail 被调用几次）；
/// 缓存用 core 的 InMemoryDatabaseProvider（真实 DAO 语义）。
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/providers/providers.dart';

/// 计数用假源
class _CountingSource extends MusicSource {
  /// getSongDetail 被调用的次数（断言"没有重复请求"就靠它）
  int detailCalls = 0;

  @override
  SourceInfo get sourceInfo =>
      SourceInfo(id: 'fake', name: 'Fake', type: SourceType.rule);

  @override
  Future<SearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 20,
  }) async =>
      SearchResult(songs: const <Song>[], sourceId: 'fake');

  @override
  Future<Song> getSongDetail(String id) async {
    detailCalls++;
    return Song(
      id: id,
      sourceId: 'fake',
      title: '标题',
      artist: '歌手',
      coverUrl: 'http://cover/$id.jpg',
      duration: 200,
    );
  }

  @override
  Future<String> getSongUrl(String id) async => 'http://audio/$id.mp3';

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
  late _CountingSource fake;
  late InMemoryDatabaseProvider db;
  late ProviderContainer container;

  /// 搜索列表给的快照：没有封面、没有时长（规则源的真实情况）
  const snapshot = Song(id: 'a', sourceId: 'fake', title: '标题', artist: '歌手');

  setUp(() async {
    fake = _CountingSource();
    db = InMemoryDatabaseProvider();
    await db.initialize();
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sourceManagerProvider
          .overrideWithValue(SourceManager()..registerSource(fake)),
    ]);
  });

  tearDown(() => container.dispose());

  test('详情已在手上：不再请求详情，但封面要落库', () async {
    // 模拟"取播放地址时顺带拿回的详情"
    final detail = await fake.getSongDetail('a');
    fake.detailCalls = 0;

    final merged = await container
        .read(songMetadataServiceProvider)
        .enrich(snapshot, detail: detail);

    expect(merged.coverUrl, 'http://cover/a.jpg', reason: 'A. enrich 返回值应带上封面');
    expect(merged.duration, 200, reason: 'B. enrich 返回值应带上传时长');
    expect(fake.detailCalls, 0, reason: 'C. 详情已在手上，不该再请求');
    final row = await db.songDao.getSong('a', 'fake');
    expect(row, isNotNull, reason: 'D. 应当落库一行');
    expect(row?.coverUrl, 'http://cover/a.jpg', reason: 'E. 库里应写入封面');
    expect(row?.duration, 200, reason: 'F. 库里应写入时长');
  });

  test('库里已有封面与时长：第二次 enrich 同样不再请求', () async {
    await db.songDao.insertSong(
      snapshot.copyWith(coverUrl: 'http://cover/a.jpg', duration: 200),
    );

    await container.read(songMetadataServiceProvider).enrich(snapshot);

    expect(fake.detailCalls, 0, reason: '库里已补齐，不该再请求');
  });

  test('确实缺封面且没有任何来源：回源请求一次（兜底保留）', () async {
    final merged = await container.read(songMetadataServiceProvider).enrich(
          const Song(id: 'b', sourceId: 'fake', title: '标题', artist: '歌手'),
        );

    expect(fake.detailCalls, 1);
    expect(merged.coverUrl, 'http://cover/b.jpg');
  });
}
