/// 播放队列模型测试（用户规则：所有播放都在某个队列里）
///
/// 规则要点（本轮落地）：
///   ① 列表页点行 = 把当前队列换成该列表；**起播成功后**才换；
///   ② 搜索候选/首页卡片等"非列表"入口 = 记入最近播放并切到最近播放队列；
///   ③ 歌单即队列 → 队列面板对歌单队列**只读**（不能拖拽/移除/清空），
///      只有最近播放可编辑；
///   ④ 起播失败（源没给地址）绝不改变当前队列。
///
/// 模拟数据：手写桩源（可切换"给地址/不给地址"）+ 假播放器 + 假播放缓存。
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/providers/providers.dart';

/// 假播放缓存：一律不命中
class _FakeCache implements AudioCache {
  @override
  Future<void> init() async {}
  @override
  Set<String> get cachedKeys => const {};
  @override
  bool isCached(String songKey) => false;
  @override
  String? localUrlFor(String songKey) => null;
  @override
  Future<String?> downloadedUrlFor(Song song) async => null;
  @override
  Future<void> cacheAfterPlay(Song song, String url,
      {Map<String, String>? headers}) async {}
  @override
  Future<int> sizeOnDisk() async => 0;
  @override
  Future<void> clear() async {}
  @override
  Stream<void> get changes => const Stream.empty();
}

/// 假播放器：记录队列与播放请求
class _FakePlayer implements Player {
  List<Song> _queue = const [];
  @override
  Stream<PlayerState> get stateStream => const Stream.empty();
  @override
  Stream<int> get positionStream => const Stream.empty();
  @override
  Stream<int> get durationStream => const Stream.empty();
  @override
  List<Song> get queue => _queue;
  @override
  void setQueue(List<Song> songs) => _queue = List.of(songs);
  @override
  Future<void> play(Song song) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('假播放器未实现该成员');
}

/// 假最近播放服务
class _FakeRecent implements RecentPlaysService {
  final List<Song> recorded = [];
  @override
  Future<void> recordPlay(Song song) async => recorded.add(song);
  @override
  Future<List<RecentPlayRecord>> getRecentPlayRecords({int limit = 500}) async =>
      const [];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('假最近播放服务未实现该成员');
}

/// 桩源：fail 为 true 时拿不到播放地址（用来验证"失败不切队列"）
class _StubSource extends MusicSource {
  /// 是否让播放地址拿不到（模拟源站没给地址）
  bool fail = false;

  @override
  SourceInfo get sourceInfo =>
      SourceInfo(id: 'stub', name: '桩源', type: SourceType.rule);

  @override
  Future<PlayableInfo> getPlayable(String id,
      {String? captchaCode, String? captchaKey}) async {
    final meta = Song(id: id, sourceId: 'stub', title: '曲' + id, artist: '');
    if (fail) return PlayableInfo(url: '', meta: meta);
    return PlayableInfo(url: 'http://audio/' + id + '.mp3', meta: meta);
  }

  @override
  Future<SearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 20,
  }) async =>
      SearchResult(songs: const <Song>[], sourceId: 'stub');
  @override
  Future<Song> getSongDetail(String id) async =>
      Song(id: id, sourceId: 'stub', title: '曲' + id, artist: '');
  @override
  Future<String> getSongUrl(String id) async => '';
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
  late ProviderContainer container;
  late _StubSource source;
  late _FakePlayer player;

  const songA = Song(id: 'a', sourceId: 'stub', title: '甲', artist: '');
  const songB = Song(id: 'b', sourceId: 'stub', title: '乙', artist: '');
  const songC = Song(id: 'c', sourceId: 'stub', title: '丙', artist: '');

  const playlistQueue = PlayQueue(
    kind: PlayQueueKind.playlist,
    id: 'p1',
    title: '默认1',
    songs: [songA, songB],
  );

  setUp(() async {
    source = _StubSource();
    player = _FakePlayer();
    final db = InMemoryDatabaseProvider();
    await db.initialize();
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      playerProvider.overrideWithValue(player),
      sourceManagerProvider
          .overrideWithValue(SourceManager()..registerSource(source)),
      audioCacheProvider.overrideWithValue(_FakeCache()),
      recentPlaysServiceProvider.overrideWithValue(_FakeRecent()),
    ]);
  });

  tearDown(() => container.dispose());

  group('队列身份与切换', () {
    test('点歌单里的歌：队列切成该歌单，身份带名字', () async {
      final ok = await container
          .read(playbackControllerProvider)
          .playInQueue(playlistQueue, startIndex: 1);

      expect(ok, isTrue);
      final queue = container.read(queueProvider);
      expect(queue.kind, PlayQueueKind.playlist);
      expect(queue.id, 'p1');
      expect(queue.title, '默认1');
      expect(queue.songs.map((s) => s.id), ['a', 'b']);
      expect(container.read(currentTrackIdProvider), songB.globalKey);
    });

    test('起播失败（源没给地址）：当前队列不变', () async {
      await container
          .read(playbackControllerProvider)
          .playInQueue(playlistQueue, startIndex: 0);
      final before = container.read(queueProvider);

      source.fail = true;
      final ok = await container.read(playbackControllerProvider).playInQueue(
            const PlayQueue(
              kind: PlayQueueKind.liked,
              title: '我喜欢的音乐',
              songs: [songC],
            ),
          );

      expect(ok, isFalse, reason: '没播起来');
      expect(container.read(queueProvider).title, before.title,
          reason: '失败绝不能把当前队列换掉');
      expect(container.read(queueProvider).kind, before.kind);
      expect(container.read(currentTrackIdProvider), songA.globalKey,
          reason: '在播的还是原来那首');
    });

    test('空队列不播也不会改队列', () async {
      final ok = await container.read(playbackControllerProvider).playInQueue(
            const PlayQueue(kind: PlayQueueKind.recent, title: '最近播放'),
          );
      expect(ok, isFalse);
      expect(container.read(queueProvider).isEmpty, isTrue);
    });
  });

  group('面板编辑权限（歌单即队列 → 只读）', () {
    test('歌单队列不可编辑：移除/追加一律无效', () async {
      await container
          .read(playbackControllerProvider)
          .playInQueue(playlistQueue, startIndex: 0);
      expect(container.read(queueProvider).editable, isFalse);

      final controller = container.read(playbackControllerProvider);
      expect(controller.removeFromQueue(1), isNull);
      expect(controller.addToQueue(songC), isFalse);

      final queue = container.read(queueProvider);
      expect(queue.songs.map((s) => s.id), ['a', 'b'],
          reason: '歌单队列的内容不能被播放器悄悄改掉');
    });

    test('最近播放队列可编辑：移除后内容真的变了', () async {
      await container.read(playbackControllerProvider).playInQueue(
            const PlayQueue(
              kind: PlayQueueKind.recent,
              title: '最近播放',
              songs: [songA, songB, songC],
            ),
            startIndex: 0,
          );
      expect(container.read(queueProvider).editable, isTrue);

      final removed =
          container.read(playbackControllerProvider).removeFromQueue(2);
      expect(removed?.id, 'c');
      expect(container.read(queueProvider).songs.map((s) => s.id), ['a', 'b']);
    });
  });
}
