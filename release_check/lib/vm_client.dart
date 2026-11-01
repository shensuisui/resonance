/// VM service 客户端：只用来调 App 侧注册的 debug-only 服务扩展。
///
/// skill §4：数据面两条通道并存 —— MCP 走能力（元素/手势/截图/日志），
/// MCP 没暴露的（App 内部状态回读）走这里。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 极简 JSON-RPC over WebSocket
class VmClient {
  final WebSocket _ws;
  final Map<int, Completer<Object?>> _pending = {};
  int _seq = 0;

  /// 主 isolate id —— 服务扩展调用必须带上它，否则 VM 拒绝路由
  String? _isolateId;

  VmClient._(this._ws);

  /// 连接 VM service（uri 形如 ws://127.0.0.1:PORT/TOKEN=/ws）
  static Future<VmClient> connect(String uri) async {
    final ws = await WebSocket.connect(uri).timeout(const Duration(seconds: 15));
    final client = VmClient._(ws);
    ws.listen((data) {
      Map<String, dynamic> msg;
      try {
        msg = jsonDecode(data.toString()) as Map<String, dynamic>;
      } catch (_) {
        return;
      }
      final id = msg['id'];
      if (id is! int) return;
      final completer = client._pending.remove(id);
      if (completer == null) return;
      if (msg.containsKey('error')) {
        completer.completeError(StateError('VM error: ' + jsonEncode(msg['error'])));
      } else {
        completer.complete(msg['result']);
      }
    });
    // 取主 isolate：ext.flutter.* 都要带 isolateId
    final vm = await client.call('getVM', const <String, Object?>{});
    final isolates = ((vm as Map)['isolates'] as List?) ?? const [];
    for (final i in isolates) {
      final m = i as Map;
      if (m['name'] == 'main') {
        client._isolateId = m['id'] as String;
        break;
      }
    }
    client._isolateId ??= (isolates.isNotEmpty ? ((isolates.first as Map)['id'] as String) : null);
    return client;
  }

  Future<Object?> call(String method, Map<String, Object?> params) {
    final id = ++_seq;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _ws.add(jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}));
    return completer.future.timeout(const Duration(seconds: 30), onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('VM 请求超时: ' + method);
    });
  }

  /// 调服务扩展，返回 data（自动 JSON 解码）
  Future<Map<String, dynamic>> callExtension(String name, [Map<String, String>? args]) async {
    final params = <String, Object?>{
      if (_isolateId != null) 'isolateId': _isolateId,
      ...?args,
    };
    final result = await call('ext.flutter.' + name, params);
    final map = (result as Map).cast<String, dynamic>();
    // Flutter 的 registerServiceExtension 会把回调返回值放进 data；
    // dart:developer.registerExtension 则把 JSON 直接平铺成 result 本身。
    final data = map['data'];
    if (data is String) {
      if (data.isEmpty) return <String, dynamic>{};
      return jsonDecode(data) as Map<String, dynamic>;
    }
    if (data is Map) return data.cast<String, dynamic>();
    return map;
  }

  /// 回读 App 状态（ext.flutter.releasecheck.state）
  Future<Map<String, dynamic>> state() => callExtension('releasecheck.state');

  /// 走 debug 扩展的命令路由（ext.flutter.releasecheck.cmd）
  Future<String> command(String cmd, [Map<String, String> extra = const {}]) async {
    final r = await callExtension('releasecheck.cmd', {'cmd': cmd, ...extra});
    return (r['result'] ?? '').toString();
  }

  Future<void> close() async {
    await _ws.close();
  }
}
