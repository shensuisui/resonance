/// 歌词缓存回归测试
///
/// 需求（用户明确要求）：歌词要在**歌曲开始播放时**就取并缓存，之后（含断网/
/// 源失效）只读缓存、不再请求远程；而不是"打开歌词页才请求"。
///
/// 这里锁定五条：
///   1. 首次 ensureLyrics 请求源，并按 LRC 文本落库；
///   2. 第二次直接命中缓存，不再请求；
///   3. 源报错且无缓存 → 返回 null（不造假歌词）；
///   4. 换了服务实例（≈重启）后仍能从库里读到缓存，0 请求；
///   5. 无时间轴的纯文本歌词原样还原（不能丢词）；同一首并发只打一次。
///
/// 模拟数据：手写假源（计数 + 可切换为报错）；缓存用 core 的
/// InMemoryDatabaseProvider（真实 DAO 语义，非假实现）。
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/providers/providers.dart';

/// 假源：歌词可计数、可切换成"源已失效"抛错
class _FakeLyricSource extends MusicSource {
  /// getLyrics 被调用的次数
  int lyricCalls = 0;

  /// 打开后模拟源失效（请求抛错）
  bool fail = false;

  /// 纯文本歌词模式（isLrc = false）
  bool plainText = false;

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
  Future<Song> getSongDetail(String id) async =>
      Song(id: id, sourceId: 'fake', title: '标题', artist: '歌手');

  @override
  Future<String> getSongUrl(String id) async => 'http://audio/$id.mp3';

  @override
  Future<Lyrics?> getLyrics(String id) async {
    lyricCalls++;
    if (fail) throw StateError('源已失效');
    if (plainText) {
      return Lyrics(
        songId: id,
        sourceId: 'fake',
        isLrc: false,
        lines: [LyricLine(time: Duration.zero, text: '第一句\n第二句')],
      );
    }
    return Lyrics(
      songId: id,
      sourceId: 'fake',
      lines: const [
        LyricLine(time: Duration.zero, text: '第一行'),
        LyricLine(time: Duration(seconds: 10), text: '第二行'),
      ],
    );
  }

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
  late _FakeLyricSource fake;
  late InMemoryDatabaseProvider db;
  late ProviderContainer container;

  /// 搜索列表给的快照
  const song = Song(id: 'x', sourceId: 'fake', title: '标题', artist: '歌手');

  /// 造一个容器（可复用同一个 db 来模拟"重启"）
  ProviderContainer make(InMemoryDatabaseProvider database) =>
      ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sourceManagerProvider
            .overrideWithValue(SourceManager()..registerSource(fake)),
      ]);

  setUp(() async {
    fake = _FakeLyricSource();
    db = InMemoryDatabaseProvider();
    await db.initialize();
    container = make(db);
  });

  tearDown(() => container.dispose());

  test('首次取词并按 LRC 落库；第二次命中缓存、不再请求', () async {
    final first = await container.read(songMetadataServiceProvider).ensureLyrics(song);
    expect(first?.lines.length, 2);
    expect(fake.lyricCalls, 1, reason: '首次应请求源');

    final row = await db.songDao.getSong('x', 'fake');
    expect(row?.lyric, contains('[00:00.00]第一行'), reason: '按 LRC 文本落库');
    expect(row?.lyric, contains('[00:10.00]第二行'));

    final second = await container.read(songMetadataServiceProvider).ensureLyrics(song);
    expect(second?.lines.length, 2);
    expect(fake.lyricCalls, 1, reason: '缓存命中不该再请求远程');
  });

  test('源报错且没有缓存 → 返回 null（不造假歌词）', () async {
    fake.fail = true;
    final got = await container.read(songMetadataServiceProvider).ensureLyrics(song);
    expect(got, isNull);
    expect(fake.lyricCalls, 1);
  });

  test('重启（换服务实例）后仍从库里读到缓存，且 0 请求', () async {
    // 先播一次把词缓存起来
    await container.read(songMetadataServiceProvider).ensureLyrics(song);
    expect(fake.lyricCalls, 1);

    // 模拟重启：新容器、同一个数据库；源此时"已失效"
    fake.fail = true;
    fake.lyricCalls = 0;
    final restarted = make(db);
    final got = await restarted.read(songMetadataServiceProvider).ensureLyrics(song);

    expect(got?.lines.length, 2, reason: '重启 + 源失效也必须能拿到缓存歌词');
    expect(fake.lyricCalls, 0, reason: '命中缓存就不该碰远程');
    restarted.dispose();
  });

  test('无时间轴的纯文本歌词原样还原（不丢词）', () async {
    fake.plainText = true;
    final first = await container.read(songMetadataServiceProvider).ensureLyrics(song);
    expect(first?.isLrc, isFalse);
    final row = await db.songDao.getSong('x', 'fake');
    expect(row?.lyric, '第一句\n第二句', reason: '纯文本按行落库');

    // 读回来仍是"整段一行"，与源侧口径一致（而不是被解析成 0 行丢弃）
    fake.lyricCalls = 0;
    final restarted = make(db);
    final got = await restarted.read(songMetadataServiceProvider).ensureLyrics(song);
    expect(got?.isLrc, isFalse);
    expect(got?.lines.length, 1);
    expect(got?.lines.first.text, '第一句\n第二句');
    expect(fake.lyricCalls, 0);
    restarted.dispose();
  });


  test('后续的时长回写不会把已缓存的歌词冲掉（真机抓到的 bug）', () async {
    final service = container.read(songMetadataServiceProvider);
    // ① 播放时先缓存歌词
    await service.ensureLyrics(song);
    expect(fake.lyricCalls, 1);
    final before = await db.songDao.getSong('x', 'fake');
    expect(before?.lyric, isNotEmpty);

    // ② 紧接着播放器回写实测时长（_persist 是 REPLACE 语义）
    await service.saveDuration(song, 240000);
    final after = await db.songDao.getSong('x', 'fake');
    expect(after?.lyric, before?.lyric, reason: '时长回写不得抹掉歌词缓存');
    expect(after?.duration, 240);

    // ③ 再读歌词：必须命中缓存，不能又去请求
    fake.lyricCalls = 0;
    final restarted = make(db);
    final got = await restarted.read(songMetadataServiceProvider).ensureLyrics(song);
    expect(got?.lines.isNotEmpty, isTrue);
    expect(fake.lyricCalls, 0, reason: '歌词已在库里，不该再请求');
    restarted.dispose();
  });


  test('同一首并发写入不互相覆盖（真机抓到的竞态）', () async {
    final service = container.read(songMetadataServiceProvider);
    // 三种写入在真实播放里几乎同时发生：歌词 / 实测时长 / 详情元数据
    await Future.wait([
      service.ensureLyrics(song),
      service.saveDuration(song, 240000),
      service.enrich(song),
    ]);

    final row = await db.songDao.getSong('x', 'fake');
    expect(row?.lyric, isNotEmpty, reason: '歌词不能被并发的其它写入冲掉');
    expect(row?.duration, 240, reason: '时长不能被冲掉');
  });

  test('同一首并发调用只打一次请求', () async {
    final results = await Future.wait([
      container.read(songMetadataServiceProvider).ensureLyrics(song),
      container.read(songMetadataServiceProvider).ensureLyrics(song),
      container.read(songMetadataServiceProvider).ensureLyrics(song),
    ]);
    expect(results.every((r) => r != null), isTrue);
    expect(fake.lyricCalls, 1, reason: '并发要按曲目键去重');
  });
}
