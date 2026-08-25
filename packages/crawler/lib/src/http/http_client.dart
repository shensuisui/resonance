import 'package:dio/dio.dart' as dio;

/// HTTP 响应
class HttpResponse {
  final dynamic data;
  final String rawData;
  final int statusCode;
  final String responseType;
  /// 重定向 URL（当 followRedirects=false 且返回 302 时有值）
  final String? redirectUrl;

  const HttpResponse({
    required this.data,
    required this.rawData,
    required this.statusCode,
    this.responseType = 'json',
    this.redirectUrl,
  });
}

/// 实例级 Cookie 管理器
///
/// 挂载在 Dio interceptor 上，自动捕获响应的 Set-Cookie 并在后续请求中回传。
/// 每个 HttpClient 实例持有独立的 _CookieInterceptor，确保不同规则源之间 cookie 隔离。
class _CookieInterceptor extends dio.Interceptor {
  /// cookie 存储：name → value
  final Map<String, String> _cookies = {};

  @override
  void onResponse(dio.Response response, dio.ResponseInterceptorHandler handler) {
    // 捕获 Set-Cookie 头，提取 name=value 存入
    final setCookies = response.headers['set-cookie'];
    if (setCookies != null) {
      for (final raw in setCookies) {
        // Set-Cookie 格式: name=value; Path=/; ...
        final pair = raw.split(';').first.trim();
        final eq = pair.indexOf('=');
        if (eq > 0) {
          final name = pair.substring(0, eq).trim();
          final value = pair.substring(eq + 1).trim();
          _cookies[name] = value;
        }
      }
    }
    handler.next(response);
  }

  @override
  void onRequest(
      dio.RequestOptions options, dio.RequestInterceptorHandler handler) {
    // 将已存 cookie 注入请求头
    if (_cookies.isNotEmpty) {
      final existing = options.headers['cookie'] as String? ?? '';
      final cookieStr = _cookies.entries
          .map((e) => '${e.key}=${e.value}')
          .join('; ');
      options.headers['cookie'] =
          existing.isEmpty ? cookieStr : '$existing; $cookieStr';
    }
    handler.next(options);
  }

  /// 清除所有 cookie（用于缓存失效时重置）
  void clear() => _cookies.clear();
}

/// HTTP 客户端封装
class HttpClient {
  final dio.Dio _dio;
  final String? _baseUrl;
  final _CookieInterceptor _cookieInterceptor = _CookieInterceptor();

  HttpClient({String? baseUrl, Duration? timeout})
      : _baseUrl = baseUrl,
        _dio = dio.Dio(dio.BaseOptions(
          connectTimeout: timeout ?? const Duration(seconds: 15),
          receiveTimeout: timeout ?? const Duration(seconds: 15),
          validateStatus: (status) => status != null && status < 400,
        )) {
    // 挂载实例级 cookie interceptor，确保 cookie 跨请求持久化且实例间隔离
    _dio.interceptors.add(_cookieInterceptor);
  }

  /// 清除缓存的 cookie（用于 preflight 缓存失效后重置认证状态）
  void clearCookies() => _cookieInterceptor.clear();

  /// 发送 GET 请求
  /// [followRedirects] 为 false 时，302 响应不跟随，返回 redirectUrl
  Future<HttpResponse> get(
    String url, {
    Map<String, String>? headers,
    String responseType = 'json',
    bool followRedirects = true,
  }) async {
    final fullUrl = _baseUrl != null ? '$_baseUrl$url' : url;
    final options = dio.Options(
      headers: headers,
      responseType: _mapResponseType(responseType),
      followRedirects: followRedirects,
      maxRedirects: followRedirects ? 5 : 0,
      validateStatus: (status) {
        // 重定向时不跟随时，3xx 也视为成功
        if (!followRedirects && status != null && status >= 300 && status < 400) {
          return true;
        }
        return status != null && status < 400;
      },
    );
    final response = await _dio.get(fullUrl, options: options);
    return _buildResponse(response, responseType);
  }

  /// 发送 POST 请求
  ///
  /// [body] 为请求体，支持 String（表单/原始文本）或 Map（JSON）
  /// [contentType] 指定 Content-Type，默认 application/x-www-form-urlencoded
  Future<HttpResponse> post(
    String url, {
    Map<String, String>? headers,
    dynamic body,
    String? contentType,
    String responseType = 'json',
    bool followRedirects = true,
  }) async {
    final fullUrl = _baseUrl != null ? '$_baseUrl$url' : url;
    final options = dio.Options(
      headers: headers,
      responseType: _mapResponseType(responseType),
      contentType:
          contentType ?? 'application/x-www-form-urlencoded',
      followRedirects: followRedirects,
      maxRedirects: followRedirects ? 5 : 0,
      validateStatus: (status) {
        if (!followRedirects && status != null && status >= 300 && status < 400) {
          return true;
        }
        return status != null && status < 400;
      },
    );
    final response = await _dio.post(fullUrl, data: body, options: options);
    return _buildResponse(response, responseType);
  }

  dio.ResponseType _mapResponseType(String type) {
    switch (type) {
      case 'text':
      case 'html':
        return dio.ResponseType.plain;
      case 'json':
      default:
        return dio.ResponseType.json;
    }
  }

  HttpResponse _buildResponse(dio.Response response, String responseType) {
    final rawData = response.data is String ? response.data : response.toString();
    // 捕获重定向 URL（302/301 响应的 Location header）
    String? redirectUrl;
    final statusCode = response.statusCode ?? 0;
    if (statusCode >= 300 && statusCode < 400) {
      final location = response.headers.value('location');
      if (location != null) {
        redirectUrl = location;
      }
    }
    return HttpResponse(
      data: response.data,
      rawData: rawData,
      statusCode: statusCode,
      responseType: responseType,
      redirectUrl: redirectUrl,
    );
  }

  /// 替换 URL 中的占位符 {key} -> value
  static String resolveUrl(String url, Map<String, String> placeholders) {
    var result = url;
    for (final entry in placeholders.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value);
    }
    return result;
  }

  /// 释放资源
  void dispose() {
    _dio.close();
  }
}