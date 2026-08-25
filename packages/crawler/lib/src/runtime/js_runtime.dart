import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../http/http_client.dart';

/// JavaScript 运行时，基于 HeadlessInAppWebView
/// 用于执行 MusicFree/落雪插件的 JS 代码
///
/// 通过 JavaScript Handler 拦截插件中的 HTTP 请求，
/// 转由 Dart 端 dio 发送，绕过 WebView 的 CORS 限制。
class JsRuntime {
  HeadlessInAppWebView? _webView;
  InAppWebViewController? _controller;
  bool _initialized = false;
  bool _disposed = false;
  final Completer<void> _readyCompleter = Completer<void>();

  /// Dart 端 HTTP 客户端，用于替代 WebView 中的 fetch
  final HttpClient _httpClient;

  JsRuntime({HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  /// 是否已初始化
  bool get isInitialized => _initialized;

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
          // 注册 HTTP 请求拦截处理器
          // JS 端通过 callHandler 发起请求，Dart 端异步完成后
          // 通过 evaluateJavascript 把结果推回 JS，避免 async 回调兼容性问题
          controller.addJavaScriptHandler(
            handlerName: 'httpRequest',
            callback: (args) {
              if (_disposed) return null;
              final config = args[0] as Map;
              final requestId = config['requestId'] as String? ?? '';
              debugPrint('[JsRuntime] HTTP 请求拦截: $requestId url=${config['url']} method=${config['method']}');
              // 异步处理 HTTP 请求，完成后推结果回 JS
              _handleHttpRequest(config).then((result) {
                if (_disposed) return;
                final dataStr = result['data']?.toString() ?? '';
                debugPrint('[JsRuntime] HTTP 响应: $requestId status=${result['status']} data=${dataStr.substring(0, dataStr.length.clamp(0, 100))}');
                final json = jsonEncode(result);
                controller.evaluateJavascript(
                  source:
                      'window.__resolveHttpRequest(${_jsString(requestId)}, $json);',
                ).then((_) {
                  debugPrint('[JsRuntime] 结果已推送回 JS: $requestId');
                }).catchError((e) {
                  debugPrint('[JsRuntime] 推送结果失败: $requestId $e');
                });
              }).catchError((e) {
                if (_disposed) return;
                debugPrint('[JsRuntime] HTTP 错误: $requestId $e');
                controller.evaluateJavascript(
                  source:
                      'window.__rejectHttpRequest(${_jsString(requestId)}, ${jsonEncode({'error': e.toString()})});',
                );
              });
              return null; // 立即返回，结果稍后推送
            },
          );
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

  /// 处理来自 JS 端的 HTTP 请求
  ///
  /// 接收格式: {requestId, url, method, data, headers}
  /// 返回格式: {data, status} 或 {error, status}
  Future<Map<String, dynamic>> _handleHttpRequest(Map<dynamic, dynamic> config) async {
    try {
      final url = config['url'] as String? ?? '';
      final method = (config['method'] as String? ?? 'GET').toUpperCase();
      final headers = <String, String>{};
      if (config['headers'] is Map) {
        (config['headers'] as Map).forEach((key, value) {
          headers[key.toString()] = value.toString();
        });
      }
      final data = config['data'];

      // 调试日志：打印完整请求信息
      final dataStr = data?.toString() ?? '';
      debugPrint('[JsRuntime] HTTP $method $url headers=$headers data=${dataStr.length > 200 ? dataStr.substring(0, 200) : dataStr}');

      if (method == 'POST' || method == 'PUT') {
        final body = data is String ? data : jsonEncode(data ?? {});
        final response = await _httpClient.post(
          url,
          headers: headers,
          body: body,
          responseType: 'text',
        );
        return {'data': response.rawData, 'status': response.statusCode};
      } else {
        final response = await _httpClient.get(
          url,
          headers: headers,
          responseType: 'text',
        );
        return {'data': response.rawData, 'status': response.statusCode};
      }
    } catch (e) {
      return {'error': e.toString(), 'status': 500};
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
  ///
  /// 使用轮询模式：启动 async 函数后立即返回，
  /// 轮询 __resultReady 直到结果就绪，再读取 __resultValue。
  /// 原因：Windows 上 evaluateJavascript 不等待 async 函数完成。
  ///
  /// [functionExpr] 可以是：
  /// - 简单方法调用：`search('keyword', 1, 'music')` → 自动加 `window.__plugin.` 前缀
  /// - 复杂表达式：以 `(` 开头 → 不加前缀，直接执行
  Future<String?> callPluginFunction(String functionExpr) async {
    await _ensureInitialized();

    // 判断是否为复杂表达式（以 ( 开头），不加 window.__plugin. 前缀
    final trimmed = functionExpr.trimLeft();
    final isComplexExpr = trimmed.startsWith('(');
    final jsExpr = isComplexExpr ? trimmed : 'window.__plugin.$functionExpr';

    // 1. 启动 async 函数（不等待完成）
    await _controller!.evaluateJavascript(source: '''
      (function() {
        window.__resultReady = false;
        window.__resultValue = null;
        (async function() {
          try {
            var result = await $jsExpr;
            window.__resultValue = JSON.stringify(result);
          } catch(e) {
            window.__resultValue = JSON.stringify({error: e.message || e.toString()});
          }
          window.__resultReady = true;
        })();
      })();
    ''');

    // 2. 轮询等待结果就绪
    const maxAttempts = 60; // 最多等待 30 秒（60 * 500ms）
    for (var i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final ready = await _controller!.evaluateJavascript(
          source: 'window.__resultReady');
      if (ready?.toString() == 'true') {
        final result = await _controller!.evaluateJavascript(
            source: 'window.__resultValue');
        return result?.toString();
      }
    }

    // 超时返回 null
    return null;
  }

  /// 检查插件是否已加载
  Future<bool> isPluginLoaded() async {
    if (!_initialized) return false;
    final result = await _controller!.evaluateJavascript(
        source: 'typeof window.__plugin !== "undefined"');
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
    _disposed = true;
    if (_webView != null) {
      await _webView!.dispose();
      _webView = null;
    }
    _controller = null;
    _initialized = false;
    _httpClient.dispose();
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) await init();
  }

  /// 将字符串转为 JS 字符串字面量（加引号，转义特殊字符）
  String _jsString(String s) {
    final escaped = s
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');
    return "'$escaped'";
  }

  /// 构建包含 polyfill 的 HTML 页面
  ///
  /// 关键设计：axios polyfill 不使用 fetch（受 CORS 限制），
  /// 而是通过 flutter_inappwebview 的 callHandler 回调到 Dart 端，
  /// 由 dio 发送真实 HTTP 请求。
  ///
  /// 完整 axios API 支持：
  /// - axios(config) / axios.get / axios.post / axios.request / axios.create
  /// - params → query string 自动转换
  /// - data 序列化（JSON / form-urlencoded）
  /// - interceptors（no-op）
  /// - defaults（timeout 等）
  String _buildPolyfillPage() {
    return '''
<!DOCTYPE html>
<html><head><meta charset="utf-8">
<script>
// === Node.js 兼容层 ===
var module = { exports: {} };
var exports = module.exports;

// 简易 require 实现
function require(name) {
  if (name === 'crypto-js') return CryptoJS;
  if (name === 'axios') return AxiosInstance;
  if (name === 'qs') return Qs;
  if (name === 'he') return He;
  if (name === 'cheerio') return Cheerio;
  if (name === 'dayjs') return { format: function() { return new Date().toISOString(); } };
  if (name === 'big-integer') return function(n) { return { toString: function() { return String(n); } }; };
  return {};
}

// === HTML 实体解码 ===
var He = {
  decode: function(text) {
    var txt = document.createElement('textarea');
    txt.innerHTML = text;
    return txt.value;
  },
  encode: function(text) {
    var txt = document.createElement('textarea');
    txt.textContent = text;
    return txt.innerHTML;
  }
};

// === qs 序列化（对象 → query string） ===
var Qs = {
  stringify: function(obj, opts) {
    if (!obj || typeof obj !== 'object') return '';
    var pairs = [];
    for (var key in obj) {
      if (obj.hasOwnProperty(key)) {
        var val = obj[key];
        if (val === undefined || val === null) continue;
        if (Array.isArray(val)) {
          for (var i = 0; i < val.length; i++) {
            pairs.push(encodeURIComponent(key) + '[]=' + encodeURIComponent(val[i]));
          }
        } else if (typeof val === 'object') {
          pairs.push(encodeURIComponent(key) + '=' + encodeURIComponent(JSON.stringify(val)));
        } else {
          pairs.push(encodeURIComponent(key) + '=' + encodeURIComponent(val));
        }
      }
    }
    return pairs.join('&');
  },
  parse: function(str) {
    var result = {};
    if (!str) return result;
    str.replace(/^\\?/, '').split('&').forEach(function(pair) {
      var idx = pair.indexOf('=');
      var key = decodeURIComponent(idx > -1 ? pair.slice(0, idx) : pair);
      var val = idx > -1 ? decodeURIComponent(pair.slice(idx + 1)) : '';
      result[key] = val;
    });
    return result;
  }
};

// === cheerio 简化实现（基于 DOMParser） ===
var Cheerio = {
  load: function(html) {
    var parser = new DOMParser();
    var doc = parser.parseFromString(html, 'text/html');
    var cheerioFn = function(selector) {
      var elements = Array.from(doc.querySelectorAll(selector));
      return {
        text: function() { return elements.map(function(e) { return e.textContent || ''; }).join(''); },
        html: function() { return elements.map(function(e) { return e.innerHTML || ''; }).join(''); },
        attr: function(name) { return elements.length ? elements[0].getAttribute(name) : undefined; },
        each: function(fn) { elements.forEach(function(e, i) { fn.call(e, i, e); }); return this; },
        find: function(sel) { return cheerioFn(sel); },
        remove: function() { elements.forEach(function(e) { e.remove(); }); return this; },
        length: elements.length,
        first: function() { return elements.length ? cheerioFn(elements[0]) : cheerioFn(''); }
      };
    };
    cheerioFn.html = function() { return doc.documentElement.outerHTML; };
    return cheerioFn;
  }
};

// === Axios polyfill ===
// 不使用 fetch（CORS 限制），改用 flutter_inappwebview.callHandler 回调 Dart 端
// Dart 端异步完成后通过 evaluateJavascript 推送结果回 JS
var __pendingHttpRequests = {};

window.__resolveHttpRequest = function(requestId, response) {
  if (__pendingHttpRequests[requestId]) {
    __pendingHttpRequests[requestId].resolve(response);
    delete __pendingHttpRequests[requestId];
  }
};

window.__rejectHttpRequest = function(requestId, error) {
  if (__pendingHttpRequests[requestId]) {
    __pendingHttpRequests[requestId].reject(error);
    delete __pendingHttpRequests[requestId];
  }
};

// 将 params 对象转为 query string
function buildQueryString(params) {
  if (!params || typeof params !== 'object') return '';
  return Qs.stringify(params);
}

// 合并 URL 和 query string
function mergeUrl(url, params) {
  var qs = buildQueryString(params);
  if (!qs) return url;
  return url + (url.indexOf('?') >= 0 ? '&' : '?') + qs;
}

// 序列化 POST data
function serializeData(data, headers) {
  if (data === undefined || data === null) return null;
  if (typeof data === 'string') return data;
  var contentType = '';
  if (headers) {
    for (var k in headers) {
      if (k.toLowerCase() === 'content-type') { contentType = headers[k]; break; }
    }
  }
  if (contentType.indexOf('application/x-www-form-urlencoded') >= 0) {
    return Qs.stringify(data);
  }
  // 默认 JSON
  return JSON.stringify(data);
}

// axios 实例工厂
function createAxiosInstance(defaultConfig) {
  var instance = function(config) {
    if (!config) return Promise.resolve({ data: {} });
    // 合并默认配置
    var merged = Object.assign({}, defaultConfig || {}, config);
    var url = mergeUrl(merged.url || '', merged.params);
    var requestId = 'req_' + Date.now() + '_' + Math.random().toString(36).substring(2);
    var headers = Object.assign({}, defaultConfig && defaultConfig.headers, merged.headers);
    var data = serializeData(merged.data, headers);
    return new Promise(function(resolve, reject) {
      __pendingHttpRequests[requestId] = { resolve: resolve, reject: reject };
      window.flutter_inappwebview.callHandler('httpRequest', {
        requestId: requestId,
        url: url,
        method: (merged.method || 'GET').toUpperCase(),
        data: data,
        headers: headers || {}
      });
    }).then(function(res) {
      // 自动解析 data 为 JSON 对象
      if (res && typeof res === 'object' && typeof res.data === 'string') {
        try { res.data = JSON.parse(res.data); } catch(e) {}
      }
      return res;
    });
  };

  instance.get = function(url, config) {
    return instance(Object.assign({}, config, { url: url, method: 'GET' }));
  };
  instance.post = function(url, data, config) {
    return instance(Object.assign({}, config, { url: url, method: 'POST', data: data }));
  };
  instance.put = function(url, data, config) {
    return instance(Object.assign({}, config, { url: url, method: 'PUT', data: data }));
  };
  instance.delete = function(url, config) {
    return instance(Object.assign({}, config, { url: url, method: 'DELETE' }));
  };
  instance.request = function(config) {
    return instance(config);
  };
  instance.create = function(config) {
    return createAxiosInstance(Object.assign({}, defaultConfig, config));
  };
  instance.interceptors = {
    request: { use: function() {} },
    response: { use: function() {} }
  };
  instance.defaults = Object.assign({ timeout: 15000, headers: {} }, defaultConfig);

  return instance;
}

var AxiosInstance = createAxiosInstance({});
AxiosInstance.default = AxiosInstance;
var Axios = AxiosInstance;

// === CryptoJS 简化实现 ===
var CryptoJS = {
  enc: {
    Base64: {
      parse: function(str) {
        return {
          toString: function(enc) {
            if (enc && enc === CryptoJS.enc.Utf8) {
              try { return decodeURIComponent(escape(atob(str))); }
              catch(e) { return atob(str); }
            }
            return str;
          }
        };
      }
    },
    Utf8: {
      stringify: function(w) { return w.toString(); }
    },
    Hex: {
      stringify: function(w) { return w.toString(); }
    }
  },
  AES: {
    encrypt: function(text, key) { return { toString: function() { return btoa(text); } }; },
    decrypt: function(ciphertext, key) { return { toString: function() { return atob(ciphertext); } }; }
  },
  MD5: function(str) {
    // 简化 MD5 — 实际应用中插件可能依赖真实 MD5
    var hash = 0, i, chr;
    for (i = 0; i < str.length; i++) {
      chr = str.charCodeAt(i);
      hash = ((hash << 5) - hash) + chr;
      hash |= 0;
    }
    return { toString: function() { return Math.abs(hash).toString(16).padStart(8, '0'); } };
  },
  SHA256: function(str) {
    return { toString: function() { return str; } };
  },
  HmacSHA256: function(str, key) {
    return { toString: function() { return str; } };
  }
};
</script>
</head><body></body></html>
''';
  }
}