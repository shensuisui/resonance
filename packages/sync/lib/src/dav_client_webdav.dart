/// [DavClient] 的 webdav_client_plus 实现
///
/// 选型见 docs/features/webdav-sync.md §2：webdav_client_plus 3.0.0，
/// 活跃维护、160/160 分，支持 Basic/Digest 与 ETag。
library;

import 'dart:typed_data';

import 'package:webdav_client_plus/webdav_client_plus.dart';

import 'dav_client.dart';

/// 基于 [WebdavClient] 的实现
class WebdavDavClient implements DavClient {
  final WebdavClient _client;

  /// 用 Basic 认证构造（用户名/密码由调用方从安全存储取出）
  WebdavDavClient({
    required String baseUrl,
    required String username,
    required String password,
  }) : _client = WebdavClient.basicAuth(
          url: baseUrl,
          user: username,
          pwd: password,
        );

  /// 去掉末尾斜杠，便于与服务器返回的 href 对齐
  String _norm(String path) {
    if (path.length > 1 && path.endsWith('/')) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }

  /// 从异常里取 HTTP 状态码
  int? _statusOf(Object error) {
    if (error is WebdavException) return error.statusCode;
    if (error is DioException) return error.response?.statusCode;
    return null;
  }

  @override
  Future<List<DavEntry>> list(String path) async {
    try {
      final files = await _client.readDir(path);
      final self = _norm(path);
      return <DavEntry>[
        for (final f in files)
          // readDir 在部分服务器上会把目录自身也返回，过滤掉
          if (_norm(f.path) != self)
            DavEntry(
              path: f.path,
              isDirectory: f.isDir,
              size: f.size,
              eTag: f.eTag,
            ),
      ];
    } on Exception catch (e) {
      final status = _statusOf(e);
      // 目录不存在按空目录处理，便于「首次同步」走空远端分支
      if (status == 404) return const <DavEntry>[];
      throw DavException('列目录失败：$path', statusCode: status);
    }
  }

  @override
  Future<List<int>?> read(String path) async {
    try {
      final bytes = await _client.read(path);
      return bytes;
    } on Exception catch (e) {
      final status = _statusOf(e);
      if (status == 404) return null;
      throw DavException('读取失败：$path', statusCode: status);
    }
  }

  @override
  Future<void> write(String path, List<int> bytes, {String? ifMatch}) async {
    try {
      await _client.write(
        path,
        Uint8List.fromList(bytes),
        headers: ifMatch == null ? null : <String, dynamic>{'If-Match': ifMatch},
      );
    } on Exception catch (e) {
      throw DavException('写入失败：$path', statusCode: _statusOf(e));
    }
  }

  @override
  Future<void> delete(String path) async {
    try {
      await _client.remove(path);
    } on Exception catch (e) {
      // 已经是「不存在」：幂等成功
      if (_statusOf(e) == 404) return;
      throw DavException('删除失败：$path', statusCode: _statusOf(e));
    }
  }

  @override
  Future<void> mkdir(String path) async {
    try {
      await _client.mkdirAll(path);
    } on Exception catch (e) {
      throw DavException('建目录失败：$path', statusCode: _statusOf(e));
    }
  }
}
