/// 资产文件存储抽象（订阅库 / 规则 / 插件）
///
/// 引擎只依赖本接口；真实实现指向 App 私有目录（壳工程注入 root 或实现），
/// 测试用内存实现。资产字节不进 DB，按路径镜像。
library;

import 'dart:io';

import 'package:crypto/crypto.dart';

/// 一个资产文件（带内容与修改时间）
class AssetFile {
  /// 相对路径（如 subscriptions/index.json）
  final String path;

  /// 字节内容
  final List<int> bytes;

  /// 修改时间（毫秒，UTC）
  final int mtime;

  /// 构造
  const AssetFile({
    required this.path,
    required this.bytes,
    required this.mtime,
  });

  /// 内容 sha256（十六进制）
  String get sha256Hex => sha256.convert(bytes).toString();
}

/// 资产存储
abstract interface class AssetStore {
  /// 读出全部资产
  Future<List<AssetFile>> readAll();

  /// 写入/覆盖指定资产（按路径）
  Future<void> write(List<AssetFile> files);

  /// 删除指定路径（仅墓碑驱动的删除用）
  Future<void> delete(Iterable<String> paths);
}

/// 内存实现（单测 / e2e）
class MemoryAssetStore implements AssetStore {
  final Map<String, AssetFile> _files = <String, AssetFile>{};

  @override
  Future<List<AssetFile>> readAll() async => _files.values.toList();

  @override
  Future<void> write(List<AssetFile> files) async {
    for (final f in files) {
      _files[f.path] = f;
    }
  }

  @override
  Future<void> delete(Iterable<String> paths) async {
    for (final p in paths) {
      _files.remove(p);
    }
  }
}

/// 文件系统实现：把 root 下的文件按相对路径镜像
///
/// [prefixes] 为空 = 镜像全部；非空则只取这些前缀（如 subscriptions/、rules/），
/// 避免把 App 私有目录里的其它文件（DB、日志）也当成资产同步出去。
class DirectoryAssetStore implements AssetStore {
  /// 根目录
  final String root;

  /// 只镜像这些相对路径前缀（空 = 全部）
  final List<String> prefixes;

  /// 构造
  const DirectoryAssetStore(this.root, {this.prefixes = const <String>[]});

  /// 该相对路径是否属于要同步的资产
  bool _allowed(String rel) =>
      prefixes.isEmpty || prefixes.any(rel.startsWith);

  /// 规范化相对路径（统一用 /，去掉前导 /）
  String _norm(String path) {
    var p = path.replaceAll('\\', '/');
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    return p;
  }

  @override
  Future<List<AssetFile>> readAll() async {
    final dir = Directory(root);
    if (!dir.existsSync()) return const <AssetFile>[];
    final out = <AssetFile>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      final rel = _norm(entity.path.substring(dir.path.length));
      if (!_allowed(rel)) continue;
      final stat = await entity.stat();
      out.add(AssetFile(
        path: rel,
        bytes: await entity.readAsBytes(),
        mtime: stat.modified.millisecondsSinceEpoch,
      ));
    }
    return out;
  }

  @override
  Future<void> write(List<AssetFile> files) async {
    for (final f in files) {
      final file = File('$root/${_norm(f.path)}');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(f.bytes, flush: true);
      // 保留来源 mtime，避免每次读回都变「更新」
      await file.setLastModified(
        DateTime.fromMillisecondsSinceEpoch(f.mtime),
      );
    }
  }

  @override
  Future<void> delete(Iterable<String> paths) async {
    for (final path in paths) {
      final file = File('$root/${_norm(path)}');
      if (await file.exists()) await file.delete();
    }
  }
}