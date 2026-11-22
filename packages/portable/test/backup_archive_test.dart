/// 备份 zip 归档测试
library;

import 'dart:convert';

import 'package:portable/portable.dart';
import 'package:test/test.dart';

void main() {
  test('zip 往返：清单 + assets 字节', () {
    final doc = BackupDocument(
      exportedAt: DateTime(2026, 11, 22),
      deviceId: 'd1',
      entities: <String, List<SyncRecord>>{
        SyncEntity.favorites: <SyncRecord>[
          SyncRecord(key: 's:1', updatedAt: 1, deviceId: 'd1', data: <String, Object?>{'songKey': 's:1'}),
        ],
      },
      assets: const <AssetEntry>[AssetEntry(path: 'rules/a.json', sha256: 'x', mtime: 3)],
    );
    final bytes = BackupArchive.encode(doc, assets: <String, List<int>>{
      'rules/a.json': utf8.encode('{"v":1}'),
    });
    final bundle = BackupArchive.decode(bytes);
    expect(bundle.document.entities[SyncEntity.favorites]!.single.key, 's:1');
    expect(utf8.decode(bundle.assets['rules/a.json']!), '{"v":1}');
  });

  test('纯 JSON（旧 .json）也能解析', () {
    final text = BackupCodec.encode(BackupDocument(exportedAt: DateTime(2026, 1, 1)));
    final bundle = BackupArchive.decode(utf8.encode(text));
    expect(bundle.document.version, 2);
    expect(bundle.assets, isEmpty);
  });
}
