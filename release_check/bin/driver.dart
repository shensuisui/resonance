/// 发版前集成检查的步骤 DSL 解释器（Flan MCP 驱动）
///
/// 数据面两条通道：
///   * MCP（flan_mcp）  —— connect / get_interactive_elements / tap / enter_text /
///                        scroll_to / take_screenshots / get_logs / get_errors / hot_reload
///   * VM service       —— 调 App 侧 debug-only 扩展 ext.flutter.releasecheck.state / .cmd
///                        （状态回读与「恢复基线」，MCP 不提供）
///
/// 退出码：0 全通过 / 1 有用例失败 / 2 环境或前置错误
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'package:release_check/mcp_client.dart';
import 'package:release_check/report.dart';
import 'package:release_check/vm_client.dart';

const Duration _pollInterval = Duration(milliseconds: 400);
const Duration _stepTimeout = Duration(seconds: 12);

Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addOption('plan', help: '用例计划 YAML')
    ..addOption('out', help: '产物目录')
    ..addOption('size', defaultsTo: 'desktop', help: '断点档名（写进报告）')
    ..addOption('only', help: '只跑一条用例')
    ..addOption('dart', help: 'dart 可执行文件（默认当前解释器）')
    ..addOption('app-dir', help: 'Flutter 工程目录（含 pubspec.yaml）')
    ..addOption('uri', help: 'VM service ws 地址（默认读 .dsh/tmp/flutter_run.uri）')
    ..addOption('index-root', help: '汇总模式：读取该目录下各尺寸 results.json 生成矩阵报告')
    ..addFlag('help', abbr: 'h', negatable: false);

  final args = parser.parse(argv);
  if (args['help'] == true) {
    stdout.writeln(parser.usage);
    return;
  }

  final rootDir = p.normalize(p.join(p.dirname(Platform.script.toFilePath()), '..', '..'));
  final appDir = p.normalize(args['app-dir'] as String? ?? p.join(rootDir, 'fm_app'));
  final dartExe = args['dart'] as String? ?? Platform.resolvedExecutable;

  // 汇总模式
  final indexRoot = args['index-root'] as String?;
  if (indexRoot != null) {
    exit(await _writeIndex(indexRoot));
  }

  final planPath = args['plan'] as String?;
  final outArg = args['out'] as String?;
  if (planPath == null || outArg == null) {
    stderr.writeln('缺少 --plan 或 --out');
    exit(2);
  }
  final outDir = p.normalize(outArg);
  final shotDir = p.join(outDir, 'screenshots');
  Directory(shotDir).createSync(recursive: true);

  final uri = args['uri'] as String? ?? _readUri(rootDir);
  if (uri == null) {
    stderr.writeln('ENV 错误：拿不到 VM service URI（先跑 run_app.ps1）');
    exit(2);
  }

  final plan = loadYaml(File(planPath).readAsStringSync()) as YamlMap;
  final cases = (plan['cases'] as YamlList).cast<YamlMap>();
  final size = args['size'] as String? ?? 'desktop';

  McpClient? mcp;
  VmClient? vm;
  try {
    mcp = await McpClient.start(dartExe: dartExe, cwd: appDir);
    await mcp.initialize();
    final tools = await mcp.listTools();
    stdout.writeln('[env] flan_mcp 工具数=' + tools.length.toString() + ' app=' + appDir);
    final conn = await mcp.callTool('connect', {'uri': uri});
    if (conn.isError) {
      stderr.writeln('[env] connect 失败: ' + conn.text);
      exit(2);
    }
    vm = await VmClient.connect(uri);
    // 就绪闸门：VM service 地址在 main() 之前就打印出来了，
    // 这时 debug 扩展可能还没注册，直接跑会一路 Unknown method。
    await _waitReady(vm);
  } catch (e) {
    stderr.writeln('ENV 错误：' + e.toString());
    if (mcp != null) stdout.writeln('[env] server stderr: ' + mcp.stderrTail.join(' | '));
    exit(2);
  }

  final runner = _Runner(mcp: mcp, vm: vm, shotDir: shotDir);
  final results = <Map<String, dynamic>>[];
  var failed = 0;

  for (final raw in cases) {
    final c = raw.cast<dynamic, dynamic>();
    final id = c['id'].toString();
    if (args['only'] != null && args['only'] != id) continue;
    final rec = await runner.runCase(id, c['title'].toString(), (c['steps'] as YamlList).cast<YamlMap>());
    if (rec['status'] == 'FAIL' || rec['status'] == 'TIMEOUT' || rec['status'] == 'ERROR') failed++;
    results.add(rec);
    stdout.writeln('[' +
        rec['status'].toString() +
        '] ' +
        id +
        ' ' +
        rec['title'].toString() +
        ' (' +
        rec['ms'].toString() +
        'ms)' +
        (rec['failStep'] == null ? '' : ' <- ' + (rec['failStep'] as Map)['error'].toString().split('\n').first));
  }

  final summary = <String, int>{};
  for (final r in results) {
    final k = r['status'] as String;
    summary[k] = (summary[k] ?? 0) + 1;
  }
  final payload = <String, dynamic>{
    'plan': planPath,
    'size': size,
    'appUri': uri,
    'startedAt': DateTime.now().toIso8601String(),
    'summary': summary,
    'results': results,
  };
  File(p.join(outDir, 'results.json')).writeAsStringSync(encodeResults(payload));
  File(p.join(outDir, 'report.md')).writeAsStringSync(renderReport(payload));

  await mcp.close();
  await vm.close();

  stdout.writeln('\n=== 汇总 === ' + jsonEncode(summary));
  stdout.writeln('产物：' + outDir);
  exit(failed > 0 ? 1 : 0);
}

/// 等到 App 侧 debug 扩展可用（状态能读回）为止
Future<void> _waitReady(VmClient vm) async {
  final deadline = DateTime.now().add(const Duration(seconds: 120));
  Object? last;
  while (DateTime.now().isBefore(deadline)) {
    try {
      final st = await vm.state();
      if (st.isNotEmpty) return;
    } catch (e) {
      last = e;
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }
  throw StateError('App 未在超时内就绪（releasecheck 扩展不可用）: ' + (last ?? '').toString());
}

String? _readUri(String rootDir) {
  final f = File(p.join(rootDir, '.dsh', 'tmp', 'flutter_run.uri'));
  if (!f.existsSync()) return null;
  final v = f.readAsStringSync().trim();
  return v.isEmpty ? null : v;
}

Future<int> _writeIndex(String root) async {
  final dir = Directory(root);
  if (!dir.existsSync()) {
    stderr.writeln('汇总目录不存在: ' + root);
    return 2;
  }
  final groups = <Map<String, dynamic>>[];
  for (final e in dir.listSync()) {
    if (e is! Directory) continue;
    final f = File(p.join(e.path, 'results.json'));
    if (!f.existsSync()) continue;
    groups.add((jsonDecode(f.readAsStringSync()) as Map).cast<String, dynamic>());
  }
  if (groups.isEmpty) {
    stderr.writeln('没有找到任何 results.json');
    return 2;
  }
  File(p.join(root, 'report.md')).writeAsStringSync(renderIndex(root, groups));
  stdout.writeln('矩阵报告已生成: ' + p.join(root, 'report.md'));
  return 0;
}

class _Runner {
  final McpClient mcp;
  final VmClient vm;
  final String shotDir;
  int _shotSeq = 0;
  String _errorBaseline = '';

  _Runner({required this.mcp, required this.vm, required this.shotDir});

  Future<Map<String, dynamic>> runCase(String id, String title, List<YamlMap> steps) async {
    final started = DateTime.now();
    final rec = <String, dynamic>{
      'id': id,
      'title': title,
      'status': 'PASS',
      'ms': 0,
      'steps': <Map<String, dynamic>>[],
      'shots': <String>[],
      'errors': <String>[],
      'failStep': null,
    };
    final vars = <String, dynamic>{};
    try {
      _errorBaseline = await _errors();
      for (var i = 0; i < steps.length; i++) {
        final step = steps[i];
        final st = DateTime.now();
        try {
          await _runStep(step, vars);
          (rec['steps'] as List).add({
            'i': i,
            'type': step['type'].toString(),
            'ok': true,
            'ms': DateTime.now().difference(st).inMilliseconds,
          });
        } catch (e) {
          final msg = e.toString();
          (rec['steps'] as List).add({
            'i': i,
            'type': step['type'].toString(),
            'ok': false,
            'ms': DateTime.now().difference(st).inMilliseconds,
            'error': msg,
          });
          if (step['soft'] == true) {
            (rec['errors'] as List).add('[soft] ' + step['type'].toString() + ': ' + msg);
            continue;
          }
          rec['failStep'] = {'i': i, 'type': step['type'].toString(), 'error': msg};
          rec['status'] = msg.toLowerCase().contains('timeout') ? 'TIMEOUT' : 'FAIL';
          throw e;
        }
      }
      (rec['shots'] as List).add(await _shot(id, false));
    } catch (_) {
      try {
        (rec['shots'] as List).add(await _shot(id, true));
      } catch (_) {
        // 截图失败不掩盖原错误
      }
    }
    // 新增异常 → WARN（不影响已有 FAIL）
    try {
      final now = await _errors();
      if (now.isNotEmpty && now != _errorBaseline) {
        (rec['errors'] as List).add(now);
        if (rec['status'] == 'PASS') rec['status'] = 'WARN';
      }
    } catch (_) {
      // get_errors 不可用时不阻塞
    }
    rec['ms'] = DateTime.now().difference(started).inMilliseconds;
    return rec;
  }

  Future<void> _runStep(Map step, Map<String, dynamic> vars) async {
    final type = step['type'].toString();
    switch (type) {
      case 'recover':
        // 顺序有讲究：先关模态浮层（否则后面的命令与被测页面都在它下面）
        await vm.command('dismiss');
        await vm.command('nowPlaying', {'open': '0'});
        await vm.command('lyrics', {'open': '0'});
        await vm.command('navigate', {'route': 'home', 'param': ''});
        await Future<void>.delayed(const Duration(milliseconds: 350));
      case 'cmd':
        final params = <String, String>{};
        step.forEach((k, v) {
          if (k == 'type' || k == 'cmd') return;
          params[k.toString()] = v.toString();
        });
        await vm.command(step['cmd'].toString(), params);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      case 'tap':
        final args = <String, Object?>{};
        if (step['key'] != null) args['key'] = step['key'].toString();
        if (step['text'] != null) args['text'] = step['text'].toString();
        if (step['wtype'] != null) args['type'] = step['wtype'].toString();
        final r = await mcp.callTool('tap', args);
        if (r.isError) throw StateError('tap 失败: ' + r.text);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      case 'tap_at':
        final r = await mcp.callTool('tap', {
          'coordinates': {
            'x': double.parse(step['x'].toString()),
            'y': double.parse(step['y'].toString()),
          },
        });
        if (r.isError) throw StateError('tap_at 失败: ' + r.text);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      case 'enter_text':
        final r = await mcp.callTool('enter_text', {
          'key': step['key'].toString(),
          'input': step['text'].toString(),
        });
        if (r.isError) throw StateError('enter_text 失败: ' + r.text);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      case 'scroll_to':
        final args = <String, Object?>{};
        if (step['key'] != null) args['key'] = step['key'].toString();
        if (step['text'] != null) args['text'] = step['text'].toString();
        final r = await mcp.callTool('scroll_to', args);
        if (r.isError) throw StateError('scroll_to 失败: ' + r.text);
      case 'expect_text':
        final ok = await _pollText(step['text'].toString());
        if (!ok) throw StateError('等不到文本: ' + step['text'].toString());
      case 'expect_text_any':
        final texts = (step['texts'] as YamlList).map((e) => e.toString()).toList();
        final deadline = DateTime.now().add(_stepTimeout);
        var hit = false;
        while (!hit && DateTime.now().isBefore(deadline)) {
          for (final t in texts) {
            if (await _pollText(t, timeout: const Duration(milliseconds: 500))) {
              hit = true;
              break;
            }
          }
        }
        if (!hit) throw StateError('候选文本一个都没出现: ' + texts.join(' | '));
      case 'expect_element_type':
        // 证据型断言：配置里登记的自定义类型是否真的出现在元素枚举结果里
        final okType = await _pollText(step['text'].toString());
        if (!okType) {
          throw StateError('元素枚举里没出现类型 ' + step['text'].toString() + '（登记 ≠ 命中）');
        }
      case 'expect_absent':
        final seen = await _pollText(step['text'].toString(), timeout: const Duration(milliseconds: 800));
        if (seen) throw StateError('不应出现的文本出现了: ' + step['text'].toString());
      case 'capture_state':
        final st = await vm.state();
        vars[step['as'].toString()] = _pick(st, step['path'].toString());
      case 'expect_state':
        final st = await vm.state();
        var actual = _pick(st, step['path'].toString());
        if (actual == 'null' || actual == '') actual = null;
        if (step['equals'] != null && actual.toString() != step['equals'].toString()) {
          throw StateError('state.' + step['path'].toString() + ' 期望 ' + step['equals'].toString() + '，实际 ' + actual.toString());
        }
        if (step['not_equals'] != null && actual.toString() == step['not_equals'].toString()) {
          throw StateError('state.' + step['path'].toString() + ' 不应等于 ' + step['not_equals'].toString());
        }
        if (step['truthy'] == true && (actual == null || actual == false)) {
          throw StateError('state.' + step['path'].toString() + ' 应为真，实际 ' + actual.toString());
        }
        if (step['falsy'] == true && actual != null && actual != false) {
          throw StateError('state.' + step['path'].toString() + ' 应为假，实际 ' + actual.toString());
        }
      case 'expect_state_differs':
        final st = await vm.state();
        final cur = _pick(st, step['path'].toString());
        final was = vars[step['from'].toString()];
        if (cur.toString() == was.toString()) {
          throw StateError('state.' + step['path'].toString() + ' 未变化，仍为 ' + cur.toString());
        }
      case 'screenshot':
        _shotSeq++;
        await _saveShot(step['name']?.toString() ?? 'step');
      case 'sleep':
        await Future<void>.delayed(Duration(milliseconds: int.tryParse(step['ms'].toString()) ?? 500));
      case 'logs':
        // Flan 一次返回上千条时，VM service 会把它编码成 Sentinel(Collected) 直接失败。
        // 重试几次（中间等 GC）仍失败就降级为空并记一条 soft 说明，不让它拖垮整条用例。
        Object? lastErr;
        var got = '';
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            final r = await mcp.callTool('get_logs');
            if (r.isError) throw StateError('get_logs 失败: ' + r.text);
            got = r.text;
            break;
          } catch (e) {
            lastErr = e;
            await Future<void>.delayed(const Duration(milliseconds: 600));
          }
        }
        vars['logs'] = got;
        if (got.isEmpty && lastErr != null) {
          throw StateError('get_logs 不可用（Sentinel 3 次）: ' + lastErr.toString());
        }
      case 'errors':
        final t = await _errors();
        if (t.isNotEmpty) vars['errors'] = t;
      case 'hot_reload':
        final r = await mcp.callTool('hot_reload');
        if (r.isError) throw StateError('hot_reload 失败: ' + r.text);
      case 'dump_elements':
        final r = await mcp.callTool('get_interactive_elements');
        final f = File(p.join(shotDir, step['name']?.toString() ?? 'elements.txt'));
        f.writeAsStringSync(r.text);
        stdout.writeln('[dump] ' + f.path + ' (' + r.text.length.toString() + ' bytes)');
      case 'note':
        break;
      default:
        throw StateError('未知 step 类型: ' + type);
    }
  }

  Object? _pick(Map<String, dynamic> state, String path) {
    Object? cur = state;
    for (final seg in path.split('.')) {
      if (cur is Map) {
        cur = cur[seg];
      } else {
        return null;
      }
    }
    return cur;
  }

  Future<bool> _pollText(String needle, {Duration? timeout}) async {
    final deadline = DateTime.now().add(timeout ?? _stepTimeout);
    do {
      final r = await mcp.callTool('get_interactive_elements');
      if (r.isError) throw StateError('get_interactive_elements 失败: ' + r.text);
      if (r.text.contains(needle)) return true;
      await Future<void>.delayed(_pollInterval);
    } while (DateTime.now().isBefore(deadline));
    return false;
  }

  Future<String> _errors() async {
    final r = await mcp.callTool('get_errors');
    if (r.isError) return '';
    final j = r.json;
    if (j is List) return j.isEmpty ? '' : r.text;
    final t = r.text.trim();
    if (t.isEmpty || t == '[]' || t == '{}' || t.toLowerCase() == 'null') return '';
    return t;
  }

  Future<String> _shot(String id, bool fail) async {
    _shotSeq++;
    final name = _shotSeq.toString().padLeft(3, '0') +
        '_' +
        id +
        (fail ? '_fail' : '') +
        '.png';
    return _saveShot(name);
  }

  Future<String> _saveShot(String name) async {
    final r = await mcp.callTool('take_screenshots');
    final b64 = r.imageBase64;
    if (b64 == null || b64.isEmpty) {
      throw StateError('截图返回空（' + r.text + '）');
    }
    final file = File(p.join(shotDir, name));
    file.writeAsBytesSync(base64Decode(b64));
    return file.path;
  }
}
