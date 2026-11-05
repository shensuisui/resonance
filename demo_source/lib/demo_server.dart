import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'demo_catalog.dart';
import 'rule_template.dart';
import 'wav.dart';

const int kDefaultDemoPort = 8787;

/// 演示曲库 HTTP 服务。
///
/// 只依赖 dart:io；数据、封面、音频都来自 demo_source 目录，不进入 App。
class DemoServer {
  final Directory root;
  final DemoCatalog catalog;
  final Map<String, List<String>> lyrics;
  final String ruleTemplate;
  final Uint8List _audio = buildDemoWav();
  HttpServer? _server;

  DemoServer._({
    required this.root,
    required this.catalog,
    required this.lyrics,
    required this.ruleTemplate,
  });

  /// 从 demo_source 根目录加载数据和歌词
  static Future<DemoServer> load(Directory root) async {
    final catalog = await DemoCatalog.load(File('${root.path}/data/catalog.json'));
    final lyrics =
        await DemoCatalog.loadLyrics(File('${root.path}/data/lyrics.json'));
    final ruleTemplate = await File('${root.path}/data/rule.json').readAsString();
    return DemoServer._(
      root: root,
      catalog: catalog,
      lyrics: lyrics,
      ruleTemplate: ruleTemplate,
    );
  }

  /// 启动服务；port=0 时由系统分配端口，返回值带真实端口。
  Future<Uri> start({
    String host = '0.0.0.0',
    int port = kDefaultDemoPort,
  }) async {
    final bound = await HttpServer.bind(host, port);
    _server = bound;
    bound.listen((request) {
      unawaited(_handle(request));
    });
    final address = bound.address.address;
    final displayHost =
        address == '0.0.0.0' || address == '::' ? '127.0.0.1' : address;
    return Uri(scheme: 'http', host: displayHost, port: bound.port);
  }

  /// 关闭服务
  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final delay = _parseDelay(request.uri.queryParameters['d']);
      if (delay == null) {
        await _sendJson(response, 400, {
          'error': 'd 必须是 0 到 300 之间的秒数（可带小数）',
        });
        return;
      }
      if (delay > 0) await Future<void>.delayed(Duration(microseconds: (delay * 1000000).round()));

      await _route(request, response);
    } catch (error, stack) {
      stderr.writeln('演示源处理失败: $error\n$stack');
      try {
        await _sendJson(response, 500, {'error': error.toString()});
      } catch (_) {
        // 响应可能已经写出，忽略二次写入异常
      }
    }
  }

  Future<void> _route(HttpRequest request, HttpResponse response) async {
    final uri = request.uri;
    final segments = uri.pathSegments;
    if (request.method != 'GET' && request.method != 'HEAD') {
      await _sendJson(response, 405, {'error': '只支持 GET/HEAD'});
      return;
    }

    if (uri.path == '/health') {
      await _sendJson(response, 200, {'status': 'ok'});
      return;
    }
    if (uri.path == '/rule.json') {
      await _sendJson(
        response,
        200,
        renderRuleTemplate(ruleTemplate, origin: _originOf(request)),
      );
      return;
    }
    if (uri.path == '/catalog.json') {
      await _sendJson(response, 200, catalog.toCatalogJson(_originOf(request)));
      return;
    }
    if (uri.path == '/search') {
      final keyword = uri.queryParameters['keyword'] ?? '';
      final page = int.tryParse(uri.queryParameters['page'] ?? '') ?? 1;
      final pageSize = (int.tryParse(uri.queryParameters['pageSize'] ?? '') ?? 20)
          .clamp(1, 100);
      final songs = catalog.search(keyword, page: page, pageSize: pageSize);
      final hasMore = catalog.searchHasMore(keyword, page: page, pageSize: pageSize);
      await _sendJson(response, 200, {
        'songs': [for (final song in songs) catalog.trackJson(song, _originOf(request))],
        'hasMore': hasMore,
        'nextPage': hasMore ? page + 1 : null,
      });
      return;
    }
    if (segments.length == 2 && segments.first == 'songs') {
      final track = catalog.track(segments[1]);
      if (track == null) {
        await _sendJson(response, 404, {'error': '没有曲目 ${segments[1]}'});
        return;
      }
      await _sendJson(response, 200, catalog.trackJson(track, _originOf(request)));
      return;
    }
    if (segments.length == 2 && segments.first == 'lyrics') {
      final lrc = _buildLrc(segments[1]);
      if (lrc == null) {
        await _sendJson(response, 404, {'error': '没有歌词 ${segments[1]}'});
        return;
      }
      await _sendText(response, 200, lrc);
      return;
    }
    if (uri.path == '/playlists') {
      await _sendJson(response, 200, {
        'playlists': [
          for (final playlist in catalog.playlists)
            catalog.playlistJson(playlist, _originOf(request)),
        ],
      });
      return;
    }
    if (segments.length == 2 && segments.first == 'playlists') {
      final playlist = catalog.playlist(segments[1]);
      if (playlist == null) {
        await _sendJson(response, 404, {'error': '没有歌单 ${segments[1]}'});
        return;
      }
      final songs = catalog.resolve(playlist.refs);
      await _sendJson(response, 200, {
        ...catalog.playlistJson(playlist, _originOf(request)),
        'songs': [for (final song in songs) catalog.trackJson(song, _originOf(request))],
      });
      return;
    }
    if (segments.length == 2 && segments.first == 'covers') {
      final name = segments[1];
      if (name.contains('/') || name.contains(r'\') || name.contains('..')) {
        await _sendJson(response, 404, {'error': '资源不存在'});
        return;
      }
      final file = File('${root.path}/covers/$name');
      if (!await file.exists()) {
        await _sendJson(response, 404, {'error': '资源不存在'});
        return;
      }
      await _sendBytes(
        request,
        response,
        await file.readAsBytes(),
        _contentTypeFor(name),
      );
      return;
    }
    if (uri.path == '/audio/demo.wav') {
      await _sendBytes(request, response, _audio, ContentType('audio', 'wav'));
      return;
    }
    await _sendJson(response, 404, {'error': '接口不存在: ${uri.path}'});
  }

  /// 延迟参数：null 表示非法；0 表示不延迟。
  double? _parseDelay(String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    final value = double.tryParse(raw);
    if (value == null || !value.isFinite || value < 0 || value > 300) return null;
    return value;
  }

  String _originOf(HttpRequest request) {
    final host = request.headers.value(HttpHeaders.hostHeader) ??
        '127.0.0.1:${_server?.port ?? kDefaultDemoPort}';
    return 'http://$host';
  }

  ContentType _contentTypeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return ContentType('image', 'png');
    if (lower.endsWith('.webp')) return ContentType('image', 'webp');
    return ContentType('image', 'jpeg');
  }

  String? _buildLrc(String id) {
    final raw = lyrics[id];
    final track = catalog.track(id);
    if (raw == null || raw.isEmpty || track == null) return null;

    final nonEmpty = raw.where((line) => line.isNotEmpty).length;
    final rawSpan = track.duration - 5 - 6;
    final span = rawSpan < 24 ? 24.0 : rawSpan.toDouble();
    final step = span / (nonEmpty == 0 ? 1 : nonEmpty);
    var index = 0;
    final buffer = StringBuffer();
    for (final line in raw) {
      if (line.isEmpty) {
        buffer.writeln();
        continue;
      }
      final millis = ((5 + step * index) * 1000).round();
      buffer.writeln('[${_stamp(Duration(milliseconds: millis))}]$line');
      index++;
    }
    return buffer.toString();
  }

  String _stamp(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    final millis = (value.inMilliseconds % 1000).toString().padLeft(3, '0').substring(0, 2);
    return '$minutes:$seconds.$millis';
  }

  Future<void> _sendJson(
    HttpResponse response,
    int status,
    Object? data,
  ) async {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.headers.set('access-control-allow-origin', '*');
    response.headers.contentLength = bytes.length;
    response.add(bytes);
    await response.close();
  }

  Future<void> _sendText(HttpResponse response, int status, String text) async {
    final bytes = Uint8List.fromList(utf8.encode(text));
    response.statusCode = status;
    response.headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.headers.contentLength = bytes.length;
    response.add(bytes);
    await response.close();
  }

  /// 支持 GET/HEAD 与单段 Range；越界返回 416。
  Future<void> _sendBytes(
    HttpRequest request,
    HttpResponse response,
    Uint8List bytes,
    ContentType contentType,
  ) async {
    response.headers.contentType = contentType;
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');

    final range = _parseRange(request.headers.value(HttpHeaders.rangeHeader), bytes.length);
    if (range == _invalidRange) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */${bytes.length}',
      );
      response.headers.contentLength = 0;
      await response.close();
      return;
    }

    final start = range?.start ?? 0;
    final end = range?.end ?? (bytes.length - 1);
    final body = bytes.sublist(start, end + 1);
    response.statusCode =
        range == null ? HttpStatus.ok : HttpStatus.partialContent;
    if (range != null) {
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/${bytes.length}',
      );
    }
    response.headers.contentLength = body.length;
    if (request.method != 'HEAD') response.add(body);
    await response.close();
  }

  static const _ByteRange _invalidRange = _ByteRange(-1, -1);

  _ByteRange? _parseRange(String? header, int total) {
    if (header == null || header.isEmpty) return null;
    if (!header.startsWith('bytes=')) return _invalidRange;
    final value = header.substring('bytes='.length).split(',').first.trim();
    final parts = value.split('-');
    if (parts.length != 2) return _invalidRange;
    final startText = parts[0].trim();
    final endText = parts[1].trim();
    if (startText.isEmpty) {
      final suffix = int.tryParse(endText);
      if (suffix == null || suffix <= 0) return _invalidRange;
      if (total == 0) return _invalidRange;
      final start = suffix >= total ? 0 : total - suffix;
      return _ByteRange(start, total - 1);
    }
    final start = int.tryParse(startText);
    if (start == null || start < 0 || start >= total) return _invalidRange;
    final end = endText.isEmpty ? total - 1 : int.tryParse(endText);
    if (end == null || end < start) return _invalidRange;
    return _ByteRange(start, end.clamp(0, total - 1));
  }
}

class _ByteRange {
  final int start;
  final int end;
  const _ByteRange(this.start, this.end);
}
