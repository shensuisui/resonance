/// 快照编解码：snapshot.json + assets/ → tar → bzip2
///
/// 压缩选型见 docs/features/webdav-sync.md §6.4 实测：
///   同一份 2.95MB JSON，tar+bzip2 -9 = 252KB（11.70x）/0.55s，
///   zip/deflate = 472KB（6.25x）；archive 的 xz 编码器实测不压缩，故不用。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'snapshot.dart';

/// 快照编解码与校验
abstract final class SnapshotCodec {
  /// 魔数（识别「这是不是回响的同步快照」）
  static const String magic = 'resonance-sync-snapshot';

  /// 当前结构版本（更高版本拒绝，低版本兼容读）
  static const int schema = 1;

  /// 快照内主文件名
  static const String snapshotFileName = 'snapshot.json';

  /// 资产目录前缀
  static const String assetsPrefix = 'assets/';

  /// 快照 → JSON Map
  static Map<String, Object?> toJson(SyncSnapshot snapshot) {
    return <String, Object?>{
      'format': magic,
      'schema': schema,
      'version': snapshot.version,
      'updatedAt': snapshot.updatedAt,
      'writer': snapshot.writer,
      'entities': <String, Object?>{
        for (final entry in snapshot.entities.entries)
          entry.key: <Object?>[for (final r in entry.value) r.toJson()],
      },
      'tombstones': <Object?>[for (final t in snapshot.tombstones) t.toJson()],
    };
  }

  /// JSON Map → 快照（校验魔数与版本）
  static SyncSnapshot fromJson(Map<String, Object?> json) {
    if (json['format'] != magic) {
      throw const SnapshotException('不是回响同步快照（magic 不匹配）');
    }
    final schemaValue = (json['schema'] as num?)?.toInt() ?? 0;
    if (schemaValue > schema) {
      throw SnapshotException('快照版本过高（$schemaValue），请升级 App 后再同步');
    }
    final entitiesJson = (json['entities'] as Map?) ?? const <String, Object?>{};
    final entities = <String, List<SyncRecord>>{};
    for (final entry in entitiesJson.entries) {
      final list = entry.value as List? ?? const <Object?>[];
      entities[entry.key as String] = <SyncRecord>[
        for (final item in list)
          SyncRecord.fromJson((item as Map).cast<String, Object?>()),
      ];
    }
    final tombstonesJson = (json['tombstones'] as List?) ?? const <Object?>[];
    return SyncSnapshot(
      version: (json['version'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      writer: json['writer'] as String? ?? '',
      entities: entities,
      tombstones: <Tombstone>[
        for (final item in tombstonesJson)
          Tombstone.fromJson((item as Map).cast<String, Object?>()),
      ],
    );
  }

  /// 打包：snapshot.json + assets/ → tar → bzip2
  static Uint8List encode(SnapshotBundle bundle) {
    final archive = Archive();
    final jsonBytes = utf8.encode(jsonEncode(toJson(bundle.snapshot)));
    archive.addFile(ArchiveFile.bytes(snapshotFileName, jsonBytes));
    for (final entry in bundle.assets.entries) {
      archive.addFile(
        ArchiveFile.bytes(assetsPrefix + entry.key, entry.value),
      );
    }
    final tarBytes = TarEncoder().encode(archive);
    final compressed = BZip2Encoder().encode(tarBytes);
    return Uint8List.fromList(compressed);
  }

  /// 解包：bzip2 → tar → (snapshot, assets)
  static SnapshotBundle decode(List<int> bytes) {
    try {
      final tarBytes = BZip2Decoder().decodeBytes(bytes);
      final archive = TarDecoder().decodeBytes(tarBytes);
      final main = archive.findFile(snapshotFileName);
      if (main == null) {
        throw const SnapshotException('快照缺少 snapshot.json');
      }
      final json = jsonDecode(utf8.decode(main.content)) as Map<String, Object?>;
      final snapshot = fromJson(json);
      final assets = <String, List<int>>{};
      for (final file in archive.files) {
        if (file.name.startsWith(assetsPrefix)) {
          assets[file.name.substring(assetsPrefix.length)] = file.content;
        }
      }
      return SnapshotBundle(snapshot: snapshot, assets: assets);
    } on SnapshotException {
      rethrow;
    } on Exception catch (e) {
      throw SnapshotException('快照解析失败：$e');
    }
  }

  /// 快照字节的 sha256（写进 latest.json，用于完整性校验）
  static String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

  /// 内容指纹：只取「实体 + key + data + 墓碑」求 sha256
  ///
  /// 刻意**不含 updatedAt / deviceId / version / writer**：写回时 DAO 会用
  /// 当前时间重写时间戳（settings/songs/playlist_songs），若把时间戳算进指纹，
  /// 每次同步都会误判为「变了」而白推一版。
  /// 语义：数据没变就不产生新版本（时间戳漂移不影响其它设备）。
  static String contentHash(SyncSnapshot snapshot) {
    final entities = <String, Object?>{};
    final names = snapshot.entities.keys.toList()..sort();
    for (final name in names) {
      final records = <SyncRecord>[...snapshot.recordsOf(name)]
        ..sort((a, b) => a.key.compareTo(b.key));
      entities[name] = <Object?>[
        for (final r in records)
          <String, Object?>{'key': r.key, 'data': _canonical(r.data)},
      ];
    }
    final tombstones = <Tombstone>[...snapshot.tombstones]
      ..sort((a, b) {
        final c = a.entity.compareTo(b.entity);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    final json = <String, Object?>{
      'entities': entities,
      'tombstones': <Object?>[
        for (final t in tombstones)
          <String, Object?>{
            'entity': t.entity,
            'key': t.key,
            'deletedAt': t.deletedAt,
          },
      ],
    };
    return sha256Hex(utf8.encode(jsonEncode(json)));
  }

  /// 递归排序 Map 键，保证指纹稳定
  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => '$k').toList()..sort();
      return <String, Object?>{
        for (final k in keys) k: _canonical(value[k]),
      };
    }
    if (value is List) {
      return <Object?>[for (final v in value) _canonical(v)];
    }
    return value;
  }
}
