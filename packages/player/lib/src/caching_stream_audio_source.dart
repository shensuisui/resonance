/// A11-M3 接线：边播边落盘的 StreamAudioSource（异步打开 sink）+ HTTP Range 打开器。
library;

import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:just_audio/just_audio.dart';

/// 打开远端流（支持 Range 时返回对应区间）。
typedef CachingStreamOpener = Future<StreamAudioResponse> Function({int? start, int? end});

/// 打开缓存写入器（返回 null 表示本次不缓存）。
typedef CacheSinkOpener = Future<AudioCacheStreamSink?> Function();

/// 播放器边读边播，同时把从头请求的字节写入缓存；完成 commit、失败 abort。
class CachingStreamAudioSource extends StreamAudioSource {
  /// 构造
  CachingStreamAudioSource({
    required this.open,
    required this.openSink,
    super.tag,
  });

  /// 远端流打开器
  final CachingStreamOpener open;

  /// 缓存写入器打开器
  final CacheSinkOpener openSink;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final response = await open(start: start, end: end);
    final caching = (start ?? 0) == 0;
    AudioCacheStreamSink? sink;
    if (caching) {
      try {
        sink = await openSink();
      } catch (_) {
        sink = null;
      }
    }
    var finished = false;
    Future<void> finish(bool ok) async {
      if (finished) return;
      finished = true;
      final s = sink;
      if (s == null) return;
      try {
        if (ok) {
          await s.commit();
        } else {
          await s.abort();
        }
      } catch (_) {}
    }

    final stream = response.stream.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (data, out) {
          final s = sink;
          if (s != null && !finished) unawaited(s.add(data));
          out.add(data);
        },
        handleDone: (out) {
          unawaited(finish(true));
          out.close();
        },
        handleError: (error, stack, out) {
          unawaited(finish(false));
          out.addError(error, stack);
          out.close();
        },
      ),
    );
    return StreamAudioResponse(
      sourceLength: response.sourceLength,
      contentLength: response.contentLength,
      offset: start ?? 0,
      stream: stream,
      contentType: response.contentType,
      rangeRequestsSupported: response.rangeRequestsSupported,
    );
  }
}

/// 用 dart:io HttpClient 打开远端音频流（带 headers；start>0 时发 Range）。
Future<StreamAudioResponse> openHttpStream(
  Uri url, {
  Map<String, String> headers = const {},
  int? start,
  int? end,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final client = HttpClient();
  final req = await client.getUrl(url);
  headers.forEach(req.headers.set);
  if (start != null && start > 0) {
    req.headers.set(
      HttpHeaders.rangeHeader,
      end == null ? 'bytes=$start-' : 'bytes=$start-$end',
    );
  }
  final resp = await req.close().timeout(timeout);
  final length = resp.contentLength >= 0 ? resp.contentLength : null;
  final offset = start ?? 0;
  final sourceLength = offset > 0 && length != null ? offset + length : length;
  final stream = resp.transform(
    StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleDone: (out) {
        client.close();
        out.close();
      },
      handleError: (e, st, out) {
        client.close(force: true);
        out.addError(e, st);
        out.close();
      },
    ),
  );
  return StreamAudioResponse(
    sourceLength: sourceLength,
    contentLength: length,
    offset: offset,
    stream: stream,
    contentType: resp.headers.contentType?.mimeType ?? 'audio/mpeg',
    rangeRequestsSupported: resp.statusCode == HttpStatus.partialContent ||
        (start == null || start == 0),
  );
}
