/// 备份归档：zip（backup.json + assets/），也兼容纯 JSON 文本
library;

import 'dart:convert';

import 'package:archive/archive.dart';

import 'backup_codec.dart';
import 'backup_model.dart';

/// 一个资产文件（供备份打包）
class BackupAssetFile {
  final String path;
  final List<int> bytes;
  final int mtime;
  const BackupAssetFile({required this.path, required this.bytes, required this.mtime});
}

/// 资产来源（由壳工程注入：读取 subscriptions/rules/plugins 目录）
abstract interface class BackupAssetSource {
  Future<List<BackupAssetFile>> readAll();
}

/// 解出的备份包
class BackupBundle {
  final BackupDocument document;
  final Map<String, List<int>> assets;
  const BackupBundle({required this.document, this.assets = const {}});
}

/// zip 编解码
abstract final class BackupArchive {
  /// zip 内清单文件名
  static const String manifestName = 'backup.json';

  /// 打包为 zip 字节
  static List<int> encode(
    BackupDocument document, {
    Map<String, List<int>> assets = const {},
  }) {
    final archive = Archive();
    final manifest = utf8.encode(BackupCodec.encode(document));
    archive.addFile(ArchiveFile(manifestName, manifest.length, manifest));
    assets.forEach((path, bytes) {
      archive.addFile(ArchiveFile('assets/$path', bytes.length, bytes));
    });
    return ZipEncoder().encode(archive);
  }

  /// 解析（zip 或纯 JSON）
  static BackupBundle decode(List<int> bytes) {
    final isZip = bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
    Archive? archive;
    if (isZip) {
      try {
        archive = ZipDecoder().decodeBytes(bytes, verify: false);
      } on Object {
        archive = null;
      }
    }
    if (archive != null) {
      ArchiveFile? manifest;
      final assets = <String, List<int>>{};
      for (final file in archive) {
        if (!file.isFile) continue;
        final data = file.content as List<int>;
        if (file.name == manifestName) {
          manifest = file;
        } else if (file.name.startsWith('assets/')) {
          assets[file.name.substring('assets/'.length)] = data;
        }
      }
      if (manifest == null) {
        throw const BackupException('压缩包内缺少 backup.json');
      }
      final text = utf8.decode(manifest.content as List<int>);
      return BackupBundle(document: BackupCodec.decode(text), assets: assets);
    }
    // 纯 JSON（旧版 .json 备份）
    final text = utf8.decode(bytes, allowMalformed: true);
    return BackupBundle(document: BackupCodec.decode(text));
  }
}
