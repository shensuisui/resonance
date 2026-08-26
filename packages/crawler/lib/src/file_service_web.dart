/// Web 平台的文件 IO 服务（空实现）
///
/// Web 不支持本地文件系统，所有操作返回空或抛异常。

/// 读取文件内容——web 不支持
Future<String> readFileAsString(String path) async {
  throw UnsupportedError('Web 平台不支持文件读取');
}

/// 读取文件字节——web 不支持
Future<List<int>> readFileAsBytes(String path) async {
  throw UnsupportedError('Web 平台不支持文件读取');
}

/// 列出目录中的文件——web 返回空
Future<List<String>> listFiles(String dirPath, {String? extension}) async {
  return [];
}

/// 检查文件是否存在——web 返回 false
Future<bool> fileExists(String path) async => false;

/// 检查路径是否是目录——web 返回 false
Future<bool> isDirectory(String path) async => false;

/// 创建目录——web 无操作
Future<void> createDirectory(String path) async {}

/// 写入文件——web 不支持
Future<void> writeFileAsBytes(String path, List<int> bytes) async {
  throw UnsupportedError('Web 平台不支持文件写入');
}

/// 写入文件（字符串）——web 不支持
Future<void> writeFileAsString(String path, String content) async {
  throw UnsupportedError('Web 平台不支持文件写入');
}

/// 获取文件大小——web 返回 0
Future<int> fileSize(String path) async => 0;
