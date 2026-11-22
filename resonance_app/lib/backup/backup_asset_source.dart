/// 备份资产来源：读取 App 私有目录下的订阅/规则/插件文件
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:portable/portable.dart';
import '../sync/sync_wiring.dart';

/// 壳工程实现：按同步同一前缀白名单收集资产
class ShellBackupAssetSource implements BackupAssetSource {
  /// App 私有根目录
  final String root;

  /// 前缀白名单（默认与云同步一致）
  final List<String> prefixes;

  /// 构造
  const ShellBackupAssetSource(this.root, {this.prefixes = SyncWiring.assetPrefixes});

  @override
  Future<List<BackupAssetFile>> readAll() async {
    final out = <BackupAssetFile>[];
    for (final prefix in prefixes) {
      final dir = Directory(p.join(root, prefix));
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        try {
          final stat = await entity.stat();
          final relative = p.relative(entity.path, from: root).replaceAll(r'\', '/');
          out.add(BackupAssetFile(
            path: relative,
            bytes: await entity.readAsBytes(),
            mtime: stat.modified.millisecondsSinceEpoch,
          ));
        } on FileSystemException {
          // 读不到就跳过
        }
      }
    }
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }
}
