/// 非 web 平台的文件 IO 服务
///
/// 使用 dart:io 的 File/Directory/FileSystemEntity。

import 'dart:io';

/// 读取文件内容为字符串
Future<String> readFileAsString(String path) async {
  return await File(path).readAsString();
}

/// 读取文件字节
Future<List<int>> readFileAsBytes(String path) async {
  return await File(path).readAsBytes();
}

/// 列出目录中的文件路径
///
/// [extension] 过滤后缀（如 '.json'），为 null 则返回所有文件。
Future<List<String>> listFiles(String dirPath, {String? extension}) async {
  final dir = Directory(dirPath);
  if (!await dir.exists()) return [];
  final entities = await dir.list().toList();
  var files = entities.whereType<File>().map((f) => f.path).toList();
  if (extension != null) {
    files = files.where((p) => p.endsWith(extension)).toList();
  }
  return files;
}

/// 检查文件是否存在
Future<bool> fileExists(String path) async {
  return await File(path).exists();
}

/// 检查路径是否是目录
Future<bool> isDirectory(String path) async {
  final type = await FileSystemEntity.type(path);
  return type == FileSystemEntityType.directory;
}

/// 创建目录
Future<void> createDirectory(String path) async {
  await Directory(path).create(recursive: true);
}

/// 写入文件
Future<void> writeFileAsBytes(String path, List<int> bytes) async {
  await File(path).writeAsBytes(bytes);
}

/// 写入文件（字符串）
Future<void> writeFileAsString(String path, String content) async {
  await File(path).writeAsString(content);
}

/// 获取文件大小
Future<int> fileSize(String path) async {
  final stat = await File(path).stat();
  return stat.size;
}
