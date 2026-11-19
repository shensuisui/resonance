/// A11-M3：把远端字节流交给 just_audio，并在从头播放时旁路写缓存。
library;

import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// 打开远端流（支持 Range 时返回对应区间）。
typedef CacheStreamOpener = Future<StreamAudioResponse> Function({int? start, int? end});

/// 旁路落盘钩子（回调由壳层提供；本类不依赖缓存实现）。
class CacheStreamHooks {
  /// 构造
  const CacheStreamHooks({this.onBytes, this.onComplete, this.onError});

  /// 收到一段字节（仅在 start==0 的完整流上触发）。
  final void Function(List<int> bytes)? onBytes;

  /// 流正常结束。
  final Future<void> Function()? onComplete;

  /// 流出错。
  final Future<void> Function(Object error)? onError;
}

/// 流式转发音源：播放器边读边播，同时把字节旁路给缓存写入。
///
/// 只有从头（start 为空或 0）请求的流才写缓存；Range 请求（seek）不写。
/// 失败时把错误继续抛给播放器，由壳层的 builder 决定回退到原始 URL。
class CacheStreamAudioSource extends StreamAudioSource {
  /// 构造
  CacheStreamAudioSource({
    required this.open,
    this.hooks = const CacheStreamHooks(),
    super.tag,
  });

  /// 远端流打开器
  final CacheStreamOpener open;

  /// 旁路落盘钩子
  final CacheStreamHooks hooks;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final response = await open(start: start, end: end);
    final caching = (start ?? 0) == 0;
    var finished = false;
    final stream = response.stream.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (data, sink) {
          if (caching && !finished) hooks.onBytes?.call(data);
          sink.add(data);
        },
        handleDone: (sink) {
          if (caching && !finished) {
            finished = true;
            final done = hooks.onComplete;
            if (done != null) unawaited(done());
          }
          sink.close();
        },
        handleError: (error, stack, sink) {
          if (caching && !finished) {
            finished = true;
            final fail = hooks.onError;
            if (fail != null) unawaited(fail(error));
          }
          sink.addError(error, stack);
          sink.close();
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
