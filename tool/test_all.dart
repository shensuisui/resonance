// 跨平台测试总入口：发现所有含 pubspec.yaml 的模块，逐个跑测试并汇总。
// 用法：dart tool/test_all.dart [--filter <子串>] [--help]
import 'dart:convert';
import 'dart:io';

class Module {
  const Module({required this.name, required this.dir, required this.flutter, required this.hasTests});
  final String name;
  final Directory dir;
  final bool flutter;
  final bool hasTests;
}

class RunResult {
  const RunResult({required this.ok, this.note = ''});
  final bool ok;
  final String note;
}

final Directory _root = _repoRoot();

Directory _repoRoot() {
  final s = Platform.script;
  if (s.scheme == 'file') {
    final toolDir = File.fromUri(s).parent;
    if (Directory('${toolDir.parent.path}/packages').existsSync()) return toolDir.parent;
  }
  return Directory.current;
}

bool _isFlutter(Directory dir) {
  final f = File('${dir.path}/pubspec.yaml');
  if (!f.existsSync()) return false;
  return f.readAsStringSync().contains('sdk: flutter');
}

Module _module(Directory d) {
  final parts = d.uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final name = parts.isEmpty ? d.path : parts.last;
  return Module(name: name, dir: d, flutter: _isFlutter(d), hasTests: Directory('${d.path}/test').existsSync());
}

List<Module> _discover(Directory root) {
  final out = <Module>[];
  final pkgs = Directory('${root.path}/packages');
  if (pkgs.existsSync()) {
    for (final d in pkgs.listSync().whereType<Directory>()) {
      if (File('${d.path}/pubspec.yaml').existsSync()) out.add(_module(d));
    }
  }
  for (final name in const ['resonance_app', 'demo_source']) {
    final d = Directory('${root.path}/$name');
    if (File('${d.path}/pubspec.yaml').existsSync()) out.add(_module(d));
  }
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}

String _exe(bool flutter) {
  final bin = '${_root.path}/.fvm/flutter_sdk/bin';
  final name = flutter ? 'flutter' : 'dart';
  final local = File('$bin/$name${Platform.isWindows ? '.bat' : ''}');
  return local.existsSync() ? local.path : name;
}

String _tail(List<String> lines) {
  final clean = lines.where((l) => l.trim().isNotEmpty).toList();
  final start = clean.length > 30 ? clean.length - 30 : 0;
  return clean.sublist(start).join(' / ');
}

/// 子进程环境：保留既有代理，但把 localhost 排除在代理外。
///
/// 本机规则源测试会起本地 HTTP 桩；若 HTTP(S)_PROXY 存在而 NO_PROXY 缺失，
/// Dart 的 findProxyFromEnvironment 会把 127.0.0.1 也送进代理，导致 502。
Map<String, String> _env() {
  final env = Map<String, String>.from(Platform.environment);
  const local = 'localhost,127.0.0.1,::1';
  for (final key in ['NO_PROXY', 'no_proxy']) {
    final cur = env[key];
    env[key] = (cur == null || cur.trim().isEmpty) ? local : '$cur,$local';
  }
  return env;
}

Future<RunResult> _run(Module m) async {
  final sw = Stopwatch()..start();
  final exe = _exe(m.flutter);
  stdout.writeln();
  stdout.writeln('=== ${m.name}（${m.flutter ? 'flutter test' : 'dart test'}）===');
  Process p;
  try {
    p = await Process.start(
      exe,
      const ['test'],
      workingDirectory: m.dir.path,
      runInShell: Platform.isWindows,
      environment: _env(),
    );
  } catch (e) {
    return RunResult(ok: false, note: '无法启动 $exe：$e');
  }
  final tail = <String>[];
  final so = p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) { stdout.writeln(l); tail.add(l); });
  final se = p.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) { stderr.writeln(l); tail.add(l); });
  int code;
  try {
    code = await p.exitCode.timeout(const Duration(minutes: 15));
  } catch (_) {
    p.kill(ProcessSignal.sigkill);
    code = -1;
  }
  await so.cancel();
  await se.cancel();
  sw.stop();
  final ok = code == 0;
  stdout.writeln('${ok ? 'PASS' : 'FAIL'} ${m.name}（${sw.elapsed.inSeconds}s，exit=$code）');
  return RunResult(ok: ok, note: ok ? '' : _tail(tail));
}

void _usage() {
  stdout.writeln('用法：dart tool/test_all.dart [--filter <子串>]');
  stdout.writeln('  --filter  只跑名字包含该子串的模块');
  stdout.writeln('  --help    显示帮助');
}

class _Args {
  const _Args(this.filter, this.help);
  final String? filter;
  final bool help;
}

_Args _parse(List<String> argv) {
  String? filter;
  var help = false;
  for (var i = 0; i < argv.length; i++) {
    final a = argv[i];
    if (a == '--help' || a == '-h') {
      help = true;
    } else if (a == '--filter' && i + 1 < argv.length) {
      filter = argv[++i];
    } else if (a.startsWith('--filter=')) {
      filter = a.substring('--filter='.length);
    }
  }
  return _Args(filter, help);
}

Future<void> main(List<String> argv) async {
  final args = _parse(argv);
  if (args.help) {
    _usage();
    return;
  }
  final filter = args.filter;
  final modules = _discover(_root).where((m) => filter == null || m.name.contains(filter)).toList();
  if (modules.isEmpty) {
    stderr.writeln('未发现可测试模块');
    exit(2);
  }
  final results = <String, RunResult>{};
  for (final m in modules) {
    if (!m.hasTests) {
      stdout.writeln();
      stdout.writeln('=== ${m.name} ===');
      stdout.writeln('SKIP 无 test/ 目录');
      results[m.name] = const RunResult(ok: true, note: 'SKIP');
      continue;
    }
    results[m.name] = await _run(m);
  }
  final failed = results.entries.where((e) => !e.value.ok).toList();
  stdout.writeln();
  stdout.writeln('================ 汇总 ================');
  for (final e in results.entries) {
    stdout.writeln('${e.value.ok ? 'PASS' : 'FAIL'}  ${e.key}');
  }
  stdout.writeln('共 ${results.length} 个模块，失败 ${failed.length} 个');
  exit(failed.isEmpty ? 0 : 1);
}
