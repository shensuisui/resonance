/// CatalogMusicSource 单元测试（lib/src/data/catalog_source.dart）。
///
/// 测什么：
///   * sourceInfo.id == demo_catalog；
///   * search：空关键字空结果、'anti' 命中 Paranoid Android、
///     分页 pageSize 生效、hasMore/nextPage 正确；
///   * getSongDetail：不存在 id 抛 StateError；
///   * getSongUrl：恒返回空串（诚实语义——演示曲库没有音频文件）；
///   * getLyrics：返回原创演示歌词（行数 = 非空行数，首行时间轴 >= 5s）；
///   * getPlaylist/getPlaylistList/getPlaylistSongs 与配表一致；
///   * getAlbum 返回 core Album 且 songs 非空。
///
/// 模拟数据来源：Catalog.build() 配表派生曲库 + kPlaylistSeeds 歌单配表。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/data/catalog.dart';
import 'package:uiv2/src/data/catalog_source.dart';
import 'package:uiv2/src/data/lyrics.dart' show kDemoLyrics;

void main() {
  late CatalogMusicSource source;

  setUp(() {
    source = CatalogMusicSource();
  });

  group('sourceInfo 与映射', () {
    test('sourceInfo.id == demo_catalog', () {
      expect(source.sourceInfo.id, 'demo_catalog');
      expect(source.sourceInfo.name, '演示曲库');
    });

    test('songOf 映射保留 core Song 字段与 extra', () {
      final track = source.catalog.track('midnights#3')!;
      final song = source.songOf(track);
      expect(song.id, 'midnights#3');
      expect(song.sourceId, 'demo_catalog');
      expect(song.globalKey, 'demo_catalog:midnights#3');
      expect(song.title, 'Anti-Hero');
      expect(song.artist, 'Taylor Swift');
      expect(song.album, 'Midnights');
      expect(song.duration, track.duration);
      expect(song.extra['genre'], '流行');
      expect(song.extra['albumId'], 'midnights');
      expect(song.extra['no'], 3);
      // midnights 在 kDownloadedAlbumIds 里，整张专辑 downloaded=true
      expect(song.extra['downloaded'], isTrue);
      expect(song.extra['local'], isFalse);
    });

    test('allSongs 数量与曲库一致', () {
      expect(source.allSongs.length, source.catalog.tracks.length);
    });
  });

  group('search', () {
    test('空关键字返回空结果', () async {
      final r = await source.search(keyword: '  ');
      expect(r.songs, isEmpty);
      expect(r.sourceId, 'demo_catalog');
    });

    test("search('anti') 命中 Anti-Hero（大小写不敏感）", () async {
      final r = await source.search(keyword: 'anti');
      expect(r.songs, isNotEmpty);
      expect(r.songs.any((s) => s.title == 'Anti-Hero'), isTrue,
          reason: 'anti 应命中 Midnights 的 Anti-Hero');
    });

    test("search('android') 命中 Paranoid Android", () async {
      final r = await source.search(keyword: 'android');
      expect(r.songs, isNotEmpty);
      expect(r.songs.any((s) => s.title == 'Paranoid Android'), isTrue,
          reason: 'android 应命中 OK Computer 的 Paranoid Android');
    });

    test("search('摇滚') 按流派命中", () async {
      final r = await source.search(keyword: '摇滚');
      expect(r.songs, isNotEmpty);
      expect(r.songs.every((s) => s.extra['genre'] == '摇滚'), isTrue);
    });

    test('分页 pageSize 生效，hasMore/nextPage 正确', () async {
      // 全量命中数
      final all = await source.search(keyword: 'the', pageSize: 1000);
      expect(all.songs.length, greaterThanOrEqualTo(4),
          reason: '前置条件：the 至少命中几首');

      final page1 = await source.search(keyword: 'the', page: 1, pageSize: 2);
      expect(page1.songs.length, 2);
      expect(page1.hasMore, isTrue);
      expect(page1.nextPage, 2);

      final page2 = await source.search(keyword: 'the', page: 2, pageSize: 2);
      expect(page2.songs.length, 2);
      // 两页拼起来等于全量的前 4 首
      expect(
        page2.songs.map((s) => s.id).toList(),
        all.songs.skip(2).take(2).map((s) => s.id).toList(),
      );

      // 最后一页：hasMore=false、nextPage=null
      final last = await source.search(
          keyword: 'the', page: (all.songs.length / 2).ceil(), pageSize: 2);
      expect(last.hasMore, isFalse);
      expect(last.nextPage, isNull);

      // 超出范围的页：空
      final beyond = await source.search(keyword: 'the', page: 99, pageSize: 2);
      expect(beyond.songs, isEmpty);
      expect(beyond.hasMore, isFalse);
    });

    test('搜索结果带 demo_catalog 前缀的 Song', () async {
      final r = await source.search(keyword: 'Come Together');
      expect(r.songs, isNotEmpty);
      for (final s in r.songs) {
        expect(s.sourceId, 'demo_catalog');
      }
    });
  });

  group('getSongDetail / getSongUrl', () {
    test('存在的 id 返回详情', () async {
      final song = await source.getSongDetail('blonde#7');
      expect(song.title, 'Self Control');
      expect(song.sourceId, 'demo_catalog');
    });

    test('不存在的 id 抛 StateError', () async {
      expect(
        () => source.getSongDetail('no-such#1'),
        throwsStateError,
      );
    });

    test('getSongUrl 恒返回空串（诚实语义）', () async {
      expect(await source.getSongUrl('midnights#3'), '');
      expect(await source.getSongUrl('不存在的id'), '');
    });
  });

  group('getLyrics', () {
    test('返回原创演示歌词：行数 = 非空行数，首行时间 >= 5s', () async {
      final lyrics = await source.getLyrics('midnights#3');
      expect(lyrics, isNotNull);
      final raw = kDemoLyrics['midnights#3']!;
      final nonEmpty = raw.where((l) => l.isNotEmpty).length;
      // 配表行数原样透传（含空行占位），非空行数应与配表一致
      expect(lyrics!.lines.where((l) => l.text.isNotEmpty).length, nonEmpty);
      // 首个非空行的时间轴 >= 5s（lead=5）
      final first = lyrics.lines.firstWhere((l) => l.text.isNotEmpty);
      expect(first.time.inMilliseconds, greaterThanOrEqualTo(5000));
      expect(lyrics.songId, 'midnights#3');
      expect(lyrics.sourceId, 'demo_catalog');
    });

    test('没有演示歌词的曲目返回 null', () async {
      expect(await source.getLyrics('kind-of-blue#1'), isNull);
    });

    test('不存在的曲目返回 null', () async {
      expect(await source.getLyrics('no-such#1'), isNull);
    });
  });

  group('getAlbum / getArtist', () {
    test('getAlbum 返回 core Album 且 songs 非空', () async {
      final album = await source.getAlbum('ok-computer');
      expect(album, isNotNull);
      expect(album!.title, 'OK Computer');
      expect(album.artist, 'Radiohead');
      expect(album.sourceId, 'demo_catalog');
      expect(album.songs, isNotEmpty);
      expect(album.songs.length, album.songCount);
      expect(album.extra['year'], 1997);
    });

    test('getAlbum 不存在的 id 返回 null', () async {
      expect(await source.getAlbum('no-such'), isNull);
    });

    test('getArtist 返回聚合信息', () async {
      final artist = await source.getArtist('Radiohead');
      expect(artist, isNotNull);
      expect(artist!.name, 'Radiohead');
      expect(artist.extra['albums'], contains('ok-computer'));
    });

    test('getArtist 不存在的名字返回 null', () async {
      expect(await source.getArtist('不存在艺人'), isNull);
    });
  });

  group('歌单接口与配表一致', () {
    test('getPlaylist 返回配表歌单，songKeys 带源前缀', () async {
      final p = await source.getPlaylist('pl-night-drive');
      expect(p, isNotNull);
      expect(p!.name, '深夜公路');
      final seed = kPlaylistSeeds.firstWhere((s) => s.id == 'pl-night-drive');
      final resolved = source.catalog.resolve(seed.refs);
      expect(p.songKeys.length, resolved.length);
      expect(
          p.songKeys.every((k) => k.startsWith('demo_catalog:')), isTrue);
      // 快照齐全
      for (final key in p.songKeys) {
        expect(p.songSnapshots.containsKey(key), isTrue);
      }
    });

    test('getPlaylist 不存在的 id 返回 null', () async {
      expect(await source.getPlaylist('no-such'), isNull);
    });

    test('getPlaylistSongs 与配表 resolve 结果一致', () async {
      final songs = await source.getPlaylistSongs('pl-focus');
      final seed = kPlaylistSeeds.firstWhere((s) => s.id == 'pl-focus');
      final resolved = source.catalog.resolve(seed.refs);
      expect(songs.map((s) => s.id).toList(),
          resolved.map((t) => t.id).toList());
    });

    test('getPlaylistSongs 不存在的 id 返回空', () async {
      expect(await source.getPlaylistSongs('no-such'), isEmpty);
    });

    test('getPlaylistList 第 1 页返回全部配表歌单', () async {
      final list = await source.getPlaylistList();
      expect(list.map((p) => p.id).toSet(),
          kPlaylistSeeds.map((s) => s.id).toSet());
      expect(list.length, kPlaylistSeeds.length);
    });

    test('getPlaylistList 第 2 页起返回空', () async {
      expect(await source.getPlaylistList(page: 2), isEmpty);
    });
  });

  group('生命周期', () {
    test('init/dispose 可安全调用', () async {
      await source.init();
      await source.dispose();
    });
  });
}
