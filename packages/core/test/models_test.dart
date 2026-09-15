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

    test('copyWith() 无参保留全部字段且与原对象相等', () {
      // 边界：不传任何参数时，copyWith 应产出一个 == 相等的副本
      final original = Song(
        id: '1', sourceId: 'test', title: 'T', artist: 'A',
        album: 'Al', coverUrl: 'http://c', duration: 100,
        playUrl: 'http://p', lyricUrl: 'http://l', lyric: 'lrc',
        localPath: '/local', extra: {'k': 'v'},
      );
      final copy = original.copyWith();
      expect(copy, original);
      expect(copy.album, 'Al');
      expect(copy.coverUrl, 'http://c');
      expect(copy.duration, 100);
      expect(copy.playUrl, 'http://p');
      expect(copy.lyricUrl, 'http://l');
      expect(copy.lyric, 'lrc');
      expect(copy.localPath, '/local');
      expect(copy.extra, {'k': 'v'});
    });

    test('copyWith 逐字段更新，其余字段保留', () {
      // 每个可选字段单独更新一次，验证不会误伤其他字段
      final original = Song(
        id: '1', sourceId: 'test', title: 'T', artist: 'A',
        album: 'Al', duration: 100,
      );
      expect(original.copyWith(artist: 'B').artist, 'B');
      expect(original.copyWith(artist: 'B').album, 'Al');
      expect(original.copyWith(album: 'NewAl').album, 'NewAl');
      expect(original.copyWith(duration: 200).duration, 200);
      expect(original.copyWith(coverUrl: 'http://x').coverUrl, 'http://x');
      expect(original.copyWith(localPath: '/p').localPath, '/p');
      // id/sourceId 也允许覆盖（用于源迁移场景）
      expect(original.copyWith(id: '2').id, '2');
      expect(original.copyWith(sourceId: 'other').sourceId, 'other');
    });

    test('copyWith 显式传 extra 时整体替换 Map', () {
      // 边界：extra 传新 Map 是替换而非合并
      final original = Song(
        id: '1', sourceId: 'test', title: 'T', artist: 'A',
        extra: {'a': 1},
      );
      final updated = original.copyWith(extra: {'b': 2});
      expect(updated.extra, {'b': 2});
      expect(updated.extra.containsKey('a'), isFalse);
    });

    test('不同 id 不相等', () {
      final a = Song(id: '1', sourceId: 'test', title: 'A', artist: 'A');
      final b = Song(id: '2', sourceId: 'test', title: 'A', artist: 'A');
      expect(a == b, isFalse);
    });

    test('Set 按 (id, sourceId) 去重', () {
      // 相等性契约的实际用途：收藏/队列去重依赖 Set 语义
      final a = Song(id: '1', sourceId: 'test', title: 'A', artist: 'A');
      final b = Song(id: '1', sourceId: 'test', title: 'B', artist: 'B');
      final c = Song(id: '1', sourceId: 'other', title: 'A', artist: 'A');
      expect({a, b, c}.length, 2, reason: 'a==b 去重，c 源不同保留');
    });

    test('toString 包含 id/sourceId/title（日志可读性）', () {
      final song = Song(id: '7', sourceId: 'src', title: '歌名', artist: 'A');
      expect(song.toString(), contains('7'));
      expect(song.toString(), contains('src'));
      expect(song.toString(), contains('歌名'));
    });
  });

  group('Album', () {
    test('creates album with required fields', () {
      final album = Album(id: '1', sourceId: 'test', title: 'Album', artist: 'A');
      expect(album.title, 'Album');
      expect(album.songs, isEmpty);
    });

    test('(id, sourceId) 相同即相等，其余字段可不同', () {
      // 相等性契约：与 Song 一致，按 (id, sourceId) 判等
      final a = Album(id: '1', sourceId: 'test', title: 'A', artist: 'X');
      final b = Album(id: '1', sourceId: 'test', title: 'B', artist: 'Y');
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('sourceId 不同不相等', () {
      final a = Album(id: '1', sourceId: 'test', title: 'A', artist: 'X');
      final b = Album(id: '1', sourceId: 'other', title: 'A', artist: 'X');
      expect(a == b, isFalse);
    });

    test('copyWith 更新 title/songs/songCount/extra', () {
      final album = Album(id: '1', sourceId: 'test', title: '旧名', artist: 'A');
      final songs = [Song(id: 's1', sourceId: 'test', title: 'T', artist: 'A')];
      final updated = album.copyWith(
        title: '新名', songs: songs, songCount: 1, extra: {'k': 'v'},
      );
      expect(updated.title, '新名');
      expect(updated.songs.length, 1);
      expect(updated.songCount, 1);
      expect(updated.extra, {'k': 'v'});
      // 未更新字段保留
      expect(updated.id, '1');
      expect(updated.artist, 'A');
    });
  });

  group('Artist', () {
    test('creates artist with required fields', () {
      final artist = Artist(id: '1', sourceId: 'test', name: 'Artist Name');
      expect(artist.name, 'Artist Name');
    });

    test('(id, sourceId) 相同即相等', () {
      final a = Artist(id: '1', sourceId: 'test', name: 'A');
      final b = Artist(id: '1', sourceId: 'test', name: 'B');
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith 更新 name/avatar/description', () {
      final artist = Artist(id: '1', sourceId: 'test', name: '旧名');
      final updated = artist.copyWith(
        name: '新名', avatar: 'http://a', description: '简介',
      );
      expect(updated.name, '新名');
      expect(updated.avatar, 'http://a');
      expect(updated.description, '简介');
      expect(updated.id, '1');
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

    test('(songId, sourceId) 相同即相等，lines 可不同', () {
      // 相等性契约：按 (songId, sourceId) 判等，与歌词内容无关
      final a = Lyrics(songId: '1', sourceId: 'test', lines: [
        LyricLine(time: Duration.zero, text: 'A'),
      ]);
      final b = Lyrics(songId: '1', sourceId: 'test', lines: []);
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith 更新 lines/isLrc，其余保留', () {
      final lyrics = Lyrics(songId: '1', sourceId: 'test');
      final newLines = [LyricLine(time: Duration(seconds: 5), text: '新行')];
      final updated = lyrics.copyWith(lines: newLines, isLrc: false);
      expect(updated.lines, newLines);
      expect(updated.isLrc, isFalse);
      expect(updated.songId, '1');
      expect(updated.sourceId, 'test');
    });

    test('lines 默认空列表、isLrc 默认 true', () {
      const lyrics = Lyrics(songId: '1', sourceId: 'test');
      expect(lyrics.lines, isEmpty);
      expect(lyrics.isLrc, isTrue);
    });

    test('LyricLine.toString 含毫秒与文本（日志可读性）', () {
      const line = LyricLine(time: Duration(milliseconds: 12340), text: '歌词');
      expect(line.toString(), contains('12340'));
      expect(line.toString(), contains('歌词'));
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

    test('id 相同即相等，name/songKeys 可不同', () {
      // 相等性契约：Playlist 只按 id 判等（本地 uuid 全局唯一）
      final now = DateTime.now();
      final a = Playlist(id: 'p1', name: 'A', createdTime: now, modifiedTime: now);
      final b = Playlist(
        id: 'p1', name: 'B', songKeys: ['s:1'],
        createdTime: now, modifiedTime: now,
      );
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith 更新 name/songKeys/modifiedTime，其余保留', () {
      final created = DateTime(2026, 1, 1);
      final modified = DateTime(2026, 1, 2);
      final playlist = Playlist(
        id: 'p1', name: '旧名', songKeys: ['a:1'],
        sourceId: 'src', sourcePlaylistId: 'sp1', coverUrl: 'http://c',
        createdTime: created, modifiedTime: created,
      );
      final updated = playlist.copyWith(
        name: '新名', songKeys: ['b:1', 'b:2'], modifiedTime: modified,
      );
      expect(updated.name, '新名');
      expect(updated.songKeys, ['b:1', 'b:2']);
      expect(updated.modifiedTime, modified);
      // 未更新字段保留
      expect(updated.id, 'p1');
      expect(updated.sourceId, 'src');
      expect(updated.sourcePlaylistId, 'sp1');
      expect(updated.coverUrl, 'http://c');
      expect(updated.createdTime, created);
    });

    test('songKeys 默认空列表', () {
      final now = DateTime.now();
      final playlist = Playlist(id: 'p1', name: 'N', createdTime: now, modifiedTime: now);
      expect(playlist.songKeys, isEmpty);
    });

    test('toString 包含 id/name/曲目数（日志可读性）', () {
      final now = DateTime.now();
      final playlist = Playlist(
        id: 'p1', name: '歌单名', songKeys: ['a:1', 'a:2'],
        createdTime: now, modifiedTime: now,
      );
      expect(playlist.toString(), contains('p1'));
      expect(playlist.toString(), contains('歌单名'));
      expect(playlist.toString(), contains('2'));
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

    test('id 相同即相等，name/type 可不同', () {
      // 相等性契约：SourceInfo 只按 id 判等（源 id 全局唯一）
      const a = SourceInfo(id: 's1', name: 'A', type: SourceType.local);
      const b = SourceInfo(id: 's1', name: 'B', type: SourceType.rule);
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('id 不同不相等', () {
      const a = SourceInfo(id: 's1', name: 'A', type: SourceType.local);
      const b = SourceInfo(id: 's2', name: 'A', type: SourceType.local);
      expect(a == b, isFalse);
    });

    test('copyWith 更新 name/iconUrl/type/enabled，其余保留', () {
      const info = SourceInfo(
        id: 's1', name: '旧名', iconUrl: 'http://old',
        type: SourceType.local, enabled: true,
      );
      final updated = info.copyWith(
        name: '新名', iconUrl: 'http://new',
        type: SourceType.rule, enabled: false,
      );
      expect(updated.name, '新名');
      expect(updated.iconUrl, 'http://new');
      expect(updated.type, SourceType.rule);
      expect(updated.enabled, isFalse);
      expect(updated.id, 's1');
    });

    test('iconUrl 默认 null、enabled 默认 true', () {
      const info = SourceInfo(id: 's1', name: 'N', type: SourceType.plugin);
      expect(info.iconUrl, isNull);
      expect(info.enabled, isTrue);
    });

    test('toString 包含 id/name/type（日志可读性）', () {
      const info = SourceInfo(id: 's1', name: '源名', type: SourceType.rule);
      expect(info.toString(), contains('s1'));
      expect(info.toString(), contains('源名'));
      expect(info.toString(), contains('rule'));
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