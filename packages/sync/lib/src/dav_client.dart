/// WebDAV 客户端抽象
///
/// 只暴露同步需要的原语（列目录 / 读 / 写 / 删 / 建目录），
/// 把具体实现（当前是 webdav_client_plus）隔离在 [DavClient] 之后，
/// 便于替换实现与用真实 WebDAV 服务器做测试。
library;

/// 目录项
class DavEntry {
  /// 相对路径（与 [DavClient.list] 传入的路径同基准）
  final String path;

  /// 是否目录
  final bool isDirectory;

  /// 字节数（目录为 null）
  final int? size;

  /// ETag（服务器提供时）
  final String? eTag;

  /// 构造
  const DavEntry({
    required this.path,
    required this.isDirectory,
    this.size,
    this.eTag,
  });

  @override
  String toString() => 'DavEntry($path, dir: $isDirectory, size: $size)';
}

/// WebDAV 操作失败（带状态码，便于同步层区分 404 / 409 / 401 等）
class DavException implements Exception {
  /// 面向用户的说明
  final String message;

  /// HTTP 状态码（协议层失败时）
  final int? statusCode;

  /// 构造
  const DavException(this.message, {this.statusCode});

  @override
  String toString() =>
      'DavException($message' + (statusCode == null ? ')' : ', $statusCode)');
}

/// WebDAV 客户端能力
abstract interface class DavClient {
  /// 列目录；目录不存在返回空列表
  Future<List<DavEntry>> list(String path);

  /// 读文件；不存在（404）返回 null
  Future<List<int>?> read(String path);

  /// 写文件；[ifMatch] 非空时作为 `If-Match` 条件（乐观并发）
  Future<void> write(String path, List<int> bytes, {String? ifMatch});

  /// 删除文件/目录；不存在忽略
  Future<void> delete(String path);

  /// 递归创建目录（已存在忽略）
  Future<void> mkdir(String path);
}
