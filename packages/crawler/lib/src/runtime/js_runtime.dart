import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// JavaScript 运行时，基于 HeadlessInAppWebView
/// 用于执行 MusicFree/落雪插件的 JS 代码
class JsRuntime {
  HeadlessInAppWebView? _webView;
  InAppWebViewController? _controller;
  bool _initialized = false;
  final Completer<void> _readyCompleter = Completer<void>();

  /// 初始化运行时
  Future<void> init() async {
    if (_initialized) return;

    try {
      _webView = HeadlessInAppWebView(
        initialData: InAppWebViewInitialData(
          data: _buildPolyfillPage(),
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          allowContentAccess: true,
          allowFileAccess: true,
          useHybridComposition: true,
        ),
        onWebViewCreated: (controller) {
          _controller = controller;
          if (!_readyCompleter.isCompleted) {
            _readyCompleter.complete();
          }
        },
      );

      await _webView!.run();

      // 等待初始化完成，超时 10 秒
      await _readyCompleter.future.timeout(const Duration(seconds: 10));
      _initialized = true;
    } catch (e) {
      // 清理资源
      if (_webView != null) {
        await _webView!.dispose();
        _webView = null;
      }
      _controller = null;
      rethrow;
    }
  }

  /// 注入插件 JS 代码
  Future<void> loadPlugin(String pluginJs) async {
    await _ensureInitialized();
    await _controller!.evaluateJavascript(source: '''
      (function() {
        const module = { exports: {} };
        $pluginJs
        window.__plugin = module.exports;
      })();
    ''');
  }

  /// 调用插件函数并获取结果
  /// [functionExpr] 如: "search('周杰伦', 1, 'music')"
  /// 返回 JSON 字符串
  Future<String?> callPluginFunction(String functionExpr) async {
    await _ensureInitialized();
    final result = await _controller!.evaluateJavascript(source: '''
      (async function() {
        try {
          const result = await window.__plugin.$functionExpr;
          return JSON.stringify(result);
        } catch(e) {
          return JSON.stringify({error: e.message || e.toString()});
        }
      })()
    ''');
    return result?.toString();
  }

  /// 检查插件是否已加载
  Future<bool> isPluginLoaded() async {
    if (!_initialized) return false;
    final result = await _controller!.evaluateJavascript(source: 'typeof window.__plugin !== "undefined"');
    return result?.toString() == 'true';
  }

  /// 检查插件是否支持某个函数
  Future<bool> hasFunction(String name) async {
    final result = await _controller!.evaluateJavascript(source: '''
      typeof window.__plugin !== "undefined" && typeof window.__plugin.$name === "function"
    ''');
    return result?.toString() == 'true';
  }

  /// 释放资源
  Future<void> dispose() async {
    if (_webView != null) {
      await _webView!.dispose();
      _webView = null;
    }
    _controller = null;
    _initialized = false;
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) await init();
  }

  /// 构建包含 polyfill 的 HTML 页面
  String _buildPolyfillPage() {
    return '''
<!DOCTYPE html>
<html><head><meta charset="utf-8">
<script>
// Node.js 兼容层
var module = { exports: {} };
var exports = module.exports;

// 简易 require 实现
function require(name) {
  if (name === 'crypto-js') return CryptoJS;
  if (name === 'he') return He;
  if (name === 'axios') return Axios;
  return {};
}

// HTML 实体解码
var He = { decode: function(text) {
  var txt = document.createElement('textarea');
  txt.innerHTML = text;
  return txt.value;
}};

// 简易 axios 实现（支持作为函数调用，也支持 .get/.post）
function AxiosInstance(config) {
  if (!config) return Promise.resolve({ data: {} });
  var method = (config.method || 'GET').toLowerCase();
  var url = config.url || '';
  var headers = config.headers || {};
  if (method === 'post' || method === 'put') {
    var body = typeof config.data === 'string' ? config.data : JSON.stringify(config.data || {});
    return fetch(url, {
      method: method.toUpperCase(),
      headers: Object.assign({'Content-Type': 'application/json'}, headers),
      body: body
    }).then(function(r) { return r.text(); })
      .then(function(text) {
        try { return { data: JSON.parse(text), status: 200 }; }
        catch(e) { return { data: text, status: 200 }; }
      });
  }
  return fetch(url, { method: method.toUpperCase(), headers: headers })
    .then(function(r) { return r.text(); })
    .then(function(text) {
      try { return { data: JSON.parse(text), status: 200 }; }
      catch(e) { return { data: text, status: 200 }; }
    });
}
AxiosInstance.get = function(url, config) {
  return AxiosInstance(Object.assign({}, config, { url: url, method: 'GET' }));
};
AxiosInstance.post = function(url, data, config) {
  return AxiosInstance(Object.assign({}, config, { url: url, method: 'POST', data: data }));
};
AxiosInstance.default = AxiosInstance;
var Axios = AxiosInstance;

// CryptoJS 简化实现
var CryptoJS = {
  enc: {
    Base64: { parse: function(str) {
      return { toString: function(enc) {
        if (enc && enc === CryptoJS.enc.Utf8) {
          try { return decodeURIComponent(escape(atob(str))); }
          catch(e) { return atob(str); }
        }
        return str;
      }};
    }},
    Utf8: { stringify: function(w) { return w.toString(); } }
  }
};
</script>
</head><body></body></html>
''';
  }
}