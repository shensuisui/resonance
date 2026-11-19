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
}
