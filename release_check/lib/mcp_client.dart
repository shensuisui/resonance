/// 极简 MCP stdio 客户端（initialize / tools/list / tools/call 三件事）
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 一次 tool 调用的结果
class McpToolResult {
  /// 服务端是否标成错误
  final bool isError;

  /// content 里所有 text 段拼接
  final String text;

  /// text 能解析成 JSON 时给出
  final Object? json;

  /// content 里有 image 段时给出 base64
  final String? imageBase64;

  const McpToolResult({
    required this.isError,
    required this.text,
    this.json,
    this.imageBase64,
  });
}

/// stdio JSON-RPC 客户端
///
/// stdout 是单播流，只能订阅一次，所以消息循环在构造函数里就建好。
class McpClient {
  final Process _proc;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final List<String> _stderrTail = [];
  late final StreamSubscription<String> _sub;
  int _seq = 0;

  McpClient._(this._proc) {
    _sub = _proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine);
    _proc.stderr.transform(utf8.decoder).listen((chunk) {
      for (final line in const LineSplitter().convert(chunk)) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        _stderrTail.add(trimmed);
        if (_stderrTail.length > 60) _stderrTail.removeAt(0);
      }
    });
  }

  /// 拉起 server：dartExe 用绝对路径；cwd 必须是含 pubspec.yaml 的包目录
  static Future<McpClient> start({
    required String dartExe,
    required String cwd,
    String package = 'flan_mcp',
  }) async {
    final proc = await Process.start(
      dartExe,
      ['run', package],
      workingDirectory: cwd,
      runInShell: false,
    );
    return McpClient._(proc);
  }

  /// stderr 尾巴（握手失败时定位用）
  List<String> get stderrTail => List.unmodifiable(_stderrTail);

  void _handleLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(trimmed) as Map<String, dynamic>;
    } catch (_) {
      return; // 非 JSON 行（编译信息等）忽略
    }
    final id = msg['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null) return;
    if (msg.containsKey('error')) {
      completer.completeError(StateError('MCP error: ' + jsonEncode(msg['error'])));
    } else {
      completer.complete((msg['result'] as Map<String, dynamic>?) ?? const {});
    }
  }

  Future<Map<String, dynamic>> _request(String method, Map<String, Object?> params) {
    final id = ++_seq;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _proc.stdin.writeln(jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    }));
    return completer.future.timeout(const Duration(seconds: 90), onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('MCP 请求超时: ' + method);
    });
  }

  /// 握手
  Future<void> initialize() async {
    await _request('initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': <String, Object?>{},
      'clientInfo': {'name': 'release-check', 'version': '1'},
    });
    _proc.stdin.writeln(jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}));
  }

  /// 工具名列表
  Future<List<String>> listTools() async {
    final result = await _request('tools/list', const {});
    final tools = (result['tools'] as List?) ?? const [];
    return [for (final t in tools) (t as Map)['name'] as String];
  }

  /// 调工具
  Future<McpToolResult> callTool(String name, [Map<String, Object?>? args]) async {
    final result = await _request('tools/call', {
      'name': name,
      'arguments': args ?? const <String, Object?>{},
    });
    final content = (result['content'] as List?) ?? const [];
    final texts = <String>[];
    String? image;
    for (final c in content) {
      final m = c as Map;
      if (m['type'] == 'text') {
        texts.add((m['text'] ?? '').toString());
      } else if (m['type'] == 'image') {
        image = (m['data'] ?? '').toString();
      }
    }
    final text = texts.join('\n');
    Object? parsed;
    if (text.isNotEmpty) {
      try {
        parsed = jsonDecode(text);
      } catch (_) {
        parsed = null;
      }
    }
    return McpToolResult(
      isError: result['isError'] == true,
      text: text,
      json: parsed,
      imageBase64: image,
    );
  }

  Future<void> close() async {
    await _sub.cancel();
    try {
      _proc.kill();
    } catch (_) {
      // 已退出
    }
  }
}
