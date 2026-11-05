import 'dart:io';

import 'package:resonance_demo_source/demo_server.dart';

Future<void> main(List<String> args) async {
  var host = '0.0.0.0';
  var port = kDefaultDemoPort;
  Directory? root;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--host':
        host = args[++i];
      case '--port':
        port = int.parse(args[++i]);
      case '--root':
        root = Directory(args[++i]);
      case '--help':
      case '-h':
        stdout.writeln('用法: dart run bin/server.dart [--host 0.0.0.0] [--port 8787] [--root <目录>]');
        return;
      default:
        stderr.writeln('未知参数: ${args[i]}');
        exitCode = 64;
        return;
    }
  }

  root ??= Directory.current;
  final server = await DemoServer.load(root);
  final origin = await server.start(host: host, port: port);
  stdout.writeln('演示曲库服务已启动: $origin');
  stdout.writeln('规则源: $origin/rule.json');
  stdout.writeln('按 Ctrl+C 停止');

  await ProcessSignal.sigint.watch().first;
  await server.close();
}
