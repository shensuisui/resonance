/// BackupCodec 单元测试
///
/// 测什么：
///   * 整包备份 JSON 的往返（歌单/收藏/最近/设置/进度全部保真）；
///   * 版本与格式校验（非 JSON、非回响备份、版本过新、缺版本号都要明确报错）；
///   * 旧版单歌单文件（v1 PlaylistIo 产物）的兼容识别。
///
/// 模拟数据来源：手工构造 BackupDocument，无文件/网络依赖。
library;

import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

/// 造一份覆盖所有分区的备份文档
BackupDocument sampleDocument() => BackupDocument(
      exportedAt: DateTime.utc(2026, 11, 12, 20, 30),
      playlists: <BackupPlaylist>[
        const BackupPlaylist(
          name: '夜行',
          songs: <BackupSong>[
            BackupSong(
              songKey: 'gequbao:1',
              title: '素颜',
              artist: '许嵩',
              duration: 259000,
              coverUrl: 'https://example.com/1.jpg',
            ),
            BackupSong(songKey: 'fengye:11', title: '若把你', artist: '小霞'),
          ],
        ),
      ],
      favorites: <BackupFavorite>[
        const BackupFavorite(
          songKey: 'gequbao:1',
          time: 1690000000000,
          title: '素颜',
          artist: '许嵩',
        ),
      ],
      recent: <BackupRecent>[
        const BackupRecent(
          songKey: 'gequbao:2',
          playedAt: 1690000001000,
          title: '山水之间',
          artist: '许嵩',
        ),
      ],
      settings: <String, String>{'theme_mode': 'dark', 'play_mode': 'list'},
      progress: <BackupProgress>[
        const BackupProgress(
          queueKind: 'playlist',
          queueId: 'p1',
          songKey: 'gequbao:1',
          positionMs: 123000,
          updatedAt: 1690000002000,
        ),
      ],
    );

void main() {
  group('BackupCodec 往返', () {
    test('编码再解码：五个分区逐项保真', () {
      final encoded = BackupCodec.encode(sampleDocument());
      final decoded = BackupCodec.decode(encoded);

      expect(decoded.playlists.length, 1);
      expect(decoded.playlists.first.name, '夜行');
      expect(decoded.playlists.first.songs.length, 2);
      expect(decoded.playlists.first.songs.first.songKey, 'gequbao:1');
      expect(decoded.playlists.first.songs.first.duration, 259000);
      expect(decoded.playlists.first.songs.first.coverUrl,
          'https://example.com/1.jpg');
      expect(decoded.playlists.first.songs.last.songKey, 'fengye:11');

      expect(decoded.favorites.single.songKey, 'gequbao:1');
      expect(decoded.favorites.single.time, 1690000000000);
      expect(decoded.recent.single.playedAt, 1690000001000);
      expect(decoded.settings['theme_mode'], 'dark');
      expect(decoded.progress.single.queueId, 'p1');
      expect(decoded.progress.single.positionMs, 123000);
    });

    test('文件头写魔数、版本与统计，便于人肉核对', () {
      final map = jsonDecode(BackupCodec.encode(sampleDocument()))
          as Map<String, dynamic>;
      expect(map['format'], kBackupFormat);
      expect(map['version'], kBackupVersion);
      expect(map['exportedAt'], '2026-11-12T20:30:00.000Z');
      final stats = map['stats'] as Map<String, dynamic>;
      expect(stats['playlists'], 1);
      expect(stats['songs'], 2);
      expect(stats['favorites'], 1);
      expect(stats['recent'], 1);
      expect(stats['settings'], 2);
      expect(stats['progress'], 1);
    });

    test('空文档也能往返（0 首歌单/空设置）', () {
      final decoded = BackupCodec.decode(BackupCodec.encode(
        BackupDocument(exportedAt: DateTime.utc(2026, 1, 1)),
      ));
      expect(decoded.playlists, isEmpty);
      expect(decoded.settings, isEmpty);
      expect(decoded.stats['songs'], 0);
    });
  });

  group('BackupCodec 校验', () {
    test('不是 JSON → 明确报错', () {
      expect(
        () => BackupCodec.decode('not a json at all'),
        throwsA(isA<BackupException>().having(
            (e) => e.message, 'message', contains('不是 JSON'))),
      );
    });

    test('是 JSON 但不是回响备份 → 明确报错', () {
      expect(
        () => BackupCodec.decode('{"hello": 1}'),
        throwsA(isA<BackupException>().having(
            (e) => e.message, 'message', contains('不是回响的备份'))),
      );
    });

    test('版本高于当前支持 → 提示先升级 App（不猜测字段）', () {
      final future = jsonEncode(<String, dynamic>{
        'format': kBackupFormat,
        'version': kBackupVersion + 1,
        'exportedAt': '2026-01-01T00:00:00Z',
      });
      expect(
        () => BackupCodec.decode(future),
        throwsA(isA<BackupException>().having(
            (e) => e.message, 'message', contains('请先升级 App'))),
      );
    });

    test('缺版本号 → 拒绝（无法判断兼容性）', () {
      final noVersion = jsonEncode(<String, dynamic>{'format': kBackupFormat});
      expect(
        () => BackupCodec.decode(noVersion),
        throwsA(isA<BackupException>().having(
            (e) => e.message, 'message', contains('缺少版本号'))),
      );
    });

    test('顶层不是对象 → 拒绝', () {
      expect(
        () => BackupCodec.decode('[]'),
        throwsA(isA<BackupException>()),
      );
    });
  });

  group('旧版单歌单兼容', () {
    test('URL 曲目按 local_custom 合成 songKey', () {
      final legacy = jsonEncode(<String, dynamic>{
        'name': '老歌单',
        'songs': <Map<String, dynamic>>[
          <String, dynamic>{
            'title': '晴天',
            'artist': '周杰伦',
            'url': 'http://example.com/a.mp3',
          },
        ],
      });
      final doc = BackupCodec.decodeLegacyPlaylist(legacy);
      expect(doc, isNotNull);
      expect(doc!.playlists.single.name, '老歌单');
      expect(doc.playlists.single.songs.single.songKey, startsWith('local_custom:'));
      expect(doc.playlists.single.songs.single.localPath, isNull);
    });

    test('本地路径曲目按 local_scan 合成 songKey 并保留路径', () {
      final legacy = jsonEncode(<String, dynamic>{
        'name': '本地',
        'songs': <Map<String, dynamic>>[
          <String, dynamic>{
            'title': 'A',
            'artist': 'B',
            'localPath': 'D:/Music/a.mp3',
          },
        ],
      });
      final doc = BackupCodec.decodeLegacyPlaylist(legacy);
      expect(doc!.playlists.single.songs.single.songKey, startsWith('local_scan:'));
      expect(doc.playlists.single.songs.single.localPath, 'D:/Music/a.mp3');
    });

    test('整包备份文件不会被当成旧版单歌单', () {
      expect(BackupCodec.decodeLegacyPlaylist(BackupCodec.encode(sampleDocument())),
          isNull);
    });

    test('旧版单歌单走 decode() 时给出可执行提示', () {
      final legacy = jsonEncode(<String, dynamic>{
        'name': 'x',
        'songs': <Map<String, dynamic>>[],
      });
      expect(
        () => BackupCodec.decode(legacy),
        throwsA(isA<BackupException>().having(
            (e) => e.message, 'message', contains('歌单详情页'))),
      );
    });
  });
}
