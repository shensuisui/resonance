/// 备份 v2 编解码 + v1 兼容测试
library;

import 'dart:convert';

import 'package:portable/portable.dart';
import 'package:test/test.dart';

SyncRecord rec(String key, int at, Map<String, Object?> data) =>
    SyncRecord(key: key, updatedAt: at, deviceId: 'd1', data: data);

void main() {
  test('v2 往返：entities 与 assets 保留', () {
    final doc = BackupDocument(
      exportedAt: DateTime.utc(2026, 11, 22, 4, 0),
      deviceId: 'd1',
      entities: <String, List<SyncRecord>>{
        SyncEntity.favorites: <SyncRecord>[
          rec('s:1', 100, <String, Object?>{'songKey': 's:1', 'time': 100, 'title': '夜行'}),
        ],
      },
      assets: const <AssetEntry>[AssetEntry(path: 'rules/a.json', sha256: 'ab', mtime: 5)],
    );
    final text = BackupCodec.encode(doc);
    final back = BackupCodec.decode(text);
    expect(back.version, 2);
    expect(back.deviceId, 'd1');
    expect(back.entities[SyncEntity.favorites]!.single.key, 's:1');
    expect(back.assets.single.path, 'rules/a.json');
    expect(back.exportedAt.toUtc(), DateTime.utc(2026, 11, 22, 4, 0));
  });

  test('v1 兼容：旧 JSON 升级为记录式（歌单 id 推导、settings 记录）', () {
    final v1 = jsonEncode(<String, Object?>{
      'format': 'resonance-backup',
      'version': 1,
      'exportedAt': '2026-11-12T20:30:00Z',
      'playlists': <Object?>[
        <String, Object?>{
          'name': '夜行',
          'songs': <Object?>[
            <String, Object?>{'songKey': 's:1', 'title': '夜行', 'artist': '陈粒'},
          ],
        },
      ],
      'favorites': <Object?>[
        <String, Object?>{'songKey': 's:2', 'time': 200, 'title': '山水'},
      ],
      'settings': <String, Object?>{'theme_mode': 'dark'},
    });
    final doc = BackupCodec.decode(v1);
    expect(doc.version, 2);
    final playlist = doc.entities[SyncEntity.playlists]!.single;
    expect(playlist.data['name'], '夜行');
    expect((playlist.data['songKeys'] as List).single, 's:1');
    expect(doc.entities[SyncEntity.favorites]!.single.updatedAt, 200);
    expect(doc.entities[SyncEntity.settings]!.single.data['value'], 'dark');
  });

  test('损坏/版本过高抛 BackupException', () {
    expect(() => BackupCodec.decode('not json'), throwsA(isA<BackupException>()));
    expect(
      () => BackupCodec.decode(jsonEncode(<String, Object?>{'format': 'x'})),
      throwsA(isA<BackupException>()),
    );
    expect(
      () => BackupCodec.decode(jsonEncode(<String, Object?>{
        'format': 'resonance-backup',
        'version': 99,
      })),
      throwsA(isA<BackupException>()),
    );
  });

  test('单歌单导出走 v2 记录', () {
    final doc = BackupCodec.singlePlaylist(name: '夜行', songs: <Map<String, Object?>>[
      <String, Object?>{'songKey': 's:1', 'title': '夜行', 'artist': '陈粒'},
    ]);
    final playlist = doc.entities[SyncEntity.playlists]!.single;
    expect(playlist.data['name'], '夜行');
    expect((playlist.data['songKeys'] as List).single, 's:1');
  });
}
