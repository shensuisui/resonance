/// 测试用真实 WebDAV 服务（shelf_dav）
///
/// 单独成包的原因：shelf_dav 依赖 xml ^6，而 webdav_client_plus 依赖 xml ^7，
/// 二者无法在同一个包内共存；所以服务端独立进程起，客户端照常依赖。
///
/// 用法：dart run bin/server.dart --dir <root> --port <port> --prefix /dav
library;

import 'dart:io' as io;

import 'package:file/local.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_dav/shelf_dav.dart';

/// 取参数
String _arg(List<String> args, String name, String fallback) {
  final i = args.indexOf(name);
  if (i >= 0 && i + 1 < args.length) return args[i + 1];
  return fallback;
}

Future<void> main(List<String> args) async {
  final root = _arg(args, '--dir', io.Directory.systemTemp.path);
  final port = int.parse(_arg(args, '--port', '0'));
  final prefix = _arg(args, '--prefix', '/dav');

  // shelf_dav 要求 package:file 的 Directory（不是 dart:io 的）
  const fs = LocalFileSystem();
  final dir = fs.directory(root)..createSync(recursive: true);
  final dav = ShelfDAV(prefix, dir);
  final server = await io.serve(dav.handler, io.InternetAddress.loopbackIPv4, port);
  io.stdout.writeln('READY ${server.port}');
  await io.stdout.flush();
  // 由测试进程 kill 退出
  await Future<void>.delayed(const Duration(days: 1));
}