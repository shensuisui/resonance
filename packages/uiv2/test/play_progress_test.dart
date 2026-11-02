/// 播放进度持久化（控制器侧）测试
///
/// 覆盖用户要求的三件事：
///   ① 边播边存：进度流的 tick 会被节流写进 play_progress；
///   ② 继续播放：resumeInQueue 从该队列上次的曲目与毫秒位置接着播；
///   ③ 没有记录时「继续播放」等同从头播（歌单详情按钮常显，靠的就是这条）。
///
/// 另外钉住两条边界：
///   * 播到结尾 3 秒内 → 记 0（下次进队列从头开始，不是"一进去就结束"）；
///   * 换队列时把旧队列的进度落盘（否则切走后旧队列的进度会停在上一次写盘处）。
///
/// 模拟数据：桩源（一律给地址）+ 假播放器（记录 seek/play）+ 内存数据库。
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/providers/providers.dart';

/// 假播放缓存：不命中
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

/// 假播放器：记录 seek 与当前曲目，够断言"从哪继续"
class _FakePlayer implements Player, AudibleSongSource {
  /// 当前队列
  List<Song> _queue = const [];

  /// 最近一次 seek 到的位置
  Duration? lastSeek;

  /// 底层"已装载"的曲目
  Song? _audible;

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
  Future<void> play(Song song) async => _audible = song;
  @override
  Future<void> jumpToIndex(int index) async {
    if (index >= 0 && index < _queue.length) _audible = _queue[index];
  }

  @override
  Future<void> prepareAt(int index, {Duration position = Duration.zero}) async {
    if (index >= 0 && index < _queue.length) _audible = _queue[index];
  }

  @override
  Future<void> seek(Duration position) async => lastSeek = position;
  @override
  Song? get audibleSong => _audible;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('假播放器未实现该成员');
}

/// 假最近播放服务
class _FakeRecent implements RecentPlaysService {
  @override
  Future<void> recordPlay(Song song) async {}
  @override
  Future<List<RecentPlayRecord>> getRecentPlayRecords({int limit = 500}) async =>
      const [];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('假最近播放服务未实现该成员');
}

/// 桩源：总是给播放地址
class _StubSource extends MusicSource {
  @override
  SourceInfo get sourceInfo =>
      SourceInfo(id: 'stub', name: '桩源', type: SourceType.rule);
  @override
  Future<PlayableInfo> getPlayable(String id,
      {String? captchaCode, String? captchaKey}) async =>
      PlayableInfo(
          url: 'http://audio/' + id + '.mp3',
          meta: Song(id: id, sourceId: 'stub', title: '曲' + id, artist: ''));
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
  late _FakePlayer player;
  late InMemoryDatabaseProvider db;

  const songA = Song(id: 'a', sourceId: 'stub', title: '甲', artist: '');
  const songB = Song(id: 'b', sourceId: 'stub', title: '乙', artist: '');
  const songC = Song(id: 'c', sourceId: 'stub', title: '丙', artist: '');

  const queue = PlayQueue(
    kind: PlayQueueKind.playlist,
    id: 'p1',
    title: '默认1',
    songs: [songA, songB, songC],
  );

  setUp(() async {
    player = _FakePlayer();
    db = InMemoryDatabaseProvider();
    await db.initialize();
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      playerProvider.overrideWithValue(player),
      sourceManagerProvider
          .overrideWithValue(SourceManager()..registerSource(_StubSource())),
      audioCacheProvider.overrideWithValue(_FakeCache()),
      recentPlaysServiceProvider.overrideWithValue(_FakeRecent()),
    ]);
  });

  tearDown(() => container.dispose());

  group('边播边存', () {
    test('进度 tick 落盘：同一队列只留一行，位置是最后一次', () async {
      final controller = container.read(playbackControllerProvider);
      await controller.playInQueue(queue, startIndex: 1);

      // 首次 tick 一定会写（还没有任何写盘记录）
      controller.onPositionTick(45000);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final saved = await db.playProgressDao.get('playlist', 'p1');
      expect(saved, isNotNull);
      expect(saved!.songKey, songB.globalKey);
      expect(saved.positionMs, 45000);
      expect((await db.playProgressDao.getAll()).length, 1);
    });

    test('播到结尾 3 秒内记 0（下次进队列从头开始）', () async {
      final controller = container.read(playbackControllerProvider);
      await controller.playInQueue(queue, startIndex: 0);
      // 时长来自 durationProvider：先摆一个 200 秒
      container.read(durationProvider.notifier).set(const Duration(seconds: 200));

      controller.onPositionTick(198000);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final saved = await db.playProgressDao.get('playlist', 'p1');
      expect(saved!.positionMs, 0, reason: '已经播完，下次不该一进去就结束');
    });

    test('切队列前把旧队列的进度落盘', () async {
      final controller = container.read(playbackControllerProvider);
      await controller.playInQueue(queue, startIndex: 2);
      controller.onPositionTick(30000);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // 切到别的队列：旧队列的进度必须已经写下去了
      await controller.playInQueue(
        const PlayQueue(
            kind: PlayQueueKind.liked, title: '我喜欢的音乐', songs: [songA]),
      );

      final old = await db.playProgressDao.get('playlist', 'p1');
      expect(old!.positionMs, 30000);
      expect(old.songKey, songC.globalKey);
    });
  });

  group('继续播放', () {
    test('有记录：从那个曲目、那个位置继续', () async {
      // 先人工写一条进度：歌单 p1 听到第 3 首的 1:12
      await db.playProgressDao.upsert(PlayProgress(
        queueKind: PlayQueueKind.playlist.name,
        queueId: 'p1',
        songKey: songC.globalKey,
        positionMs: 72000,
        updatedAt: 1,
      ));

      final ok =
          await container.read(playbackControllerProvider).resumeInQueue(queue);

      expect(ok, isTrue);
      // 断言当前曲目：假播放器不实现 CurrentSongSource，所以看控制器直接写的 id
      expect(container.read(currentTrackIdProvider), songC.globalKey,
          reason: '要接着上次那首');
      expect(player.lastSeek, const Duration(milliseconds: 72000),
          reason: '要落回上次的毫秒位置');
    });

    test('没有记录：等同从头播（不 seek）', () async {
      final ok =
          await container.read(playbackControllerProvider).resumeInQueue(queue);

      expect(ok, isTrue);
      expect(container.read(currentTrackIdProvider), songA.globalKey);
      expect(player.lastSeek, isNull, reason: '没记录就不该乱 seek');
    });

    test('记录里的歌已不在队列：退回第一首，不崩', () async {
      await db.playProgressDao.upsert(PlayProgress(
        queueKind: PlayQueueKind.playlist.name,
        queueId: 'p1',
        songKey: 'stub:gone',
        positionMs: 5000,
        updatedAt: 1,
      ));

      final ok =
          await container.read(playbackControllerProvider).resumeInQueue(queue);

      expect(ok, isTrue);
      expect(container.read(currentTrackIdProvider), songA.globalKey);
      expect(player.lastSeek, isNull);
    });
  });

  group('预置（启动恢复）', () {
    test('prepareQueue：装好曲目、摆好位置，但不播（状态不是 playing）', () async {
      await container.read(playbackControllerProvider).prepareQueue(
            queue,
            1,
            const Duration(milliseconds: 90000),
          );

      expect(container.read(queueProvider).title, '默认1',
          reason: '装成功了才把当前队列换过去');
      expect(container.read(currentTrackIdProvider), songB.globalKey);
      expect(container.read(positionProvider), const Duration(milliseconds: 90000));
      expect(container.read(isPlayingProvider), isFalse, reason: '打开 App 不该自动出声');
    });
  });
}
