import 'package:dio/dio.dart' as dio;

/// HTTP 响应
class HttpResponse {
  final dynamic data;
  final String rawData;
  final int statusCode;
  final String responseType;

  const HttpResponse({
    required this.data,
    required this.rawData,
    required this.statusCode,
    this.responseType = 'json',
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
        ));

  /// 发送 GET 请求
  Future<HttpResponse> get(
    String url, {
    Map<String, String>? headers,
    String responseType = 'json',
  }) async {
    final fullUrl = _baseUrl != null ? '$_baseUrl$url' : url;
    final options = dio.Options(
      headers: headers,
      responseType: _mapResponseType(responseType),
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
    return HttpResponse(
      data: response.data,
      rawData: rawData,
      statusCode: response.statusCode ?? 0,
      responseType: responseType,
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