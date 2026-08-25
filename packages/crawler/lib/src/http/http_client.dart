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

/// HTTP 客户端封装
class HttpClient {
  final dio.Dio _dio;
  final String? _baseUrl;

  HttpClient({String? baseUrl, Duration? timeout})
      : _baseUrl = baseUrl,
        _dio = dio.Dio(dio.BaseOptions(
          connectTimeout: timeout ?? const Duration(seconds: 15),
          receiveTimeout: timeout ?? const Duration(seconds: 15),
          validateStatus: (status) => status != null && status < 400,
        ));

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
  Future<HttpResponse> post(
    String url, {
    Map<String, String>? headers,
    dynamic body,
    String responseType = 'json',
  }) async {
    final fullUrl = _baseUrl != null ? '$_baseUrl$url' : url;
    final options = dio.Options(
      headers: headers,
      responseType: _mapResponseType(responseType),
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