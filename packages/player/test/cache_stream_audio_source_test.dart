/// A11-M3：CacheStreamAudioSource 边转发边旁路 + Range 请求不写缓存 + 错误透传
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:player/player.dart';

StreamAudioResponse _resp(Stream<List<int>> stream, {int length = 3}) =>
    StreamAudioResponse(
      sourceLength: length,
      contentLength: length,
      offset: 0,
      stream: stream,
      contentType: 'audio/mpeg',
    );

void main() {
  test('从头请求：字节旁路写出并在结束时 complete', () async {
    final chunks = <List<int>>[];
    var done = 0;
    final source = CacheStreamAudioSource(
      open: ({int? start, int? end}) async =>
          _resp(Stream.fromIterable([<int>[1, 2], <int>[3]])),
      hooks: CacheStreamHooks(
        onBytes: chunks.add,
        onComplete: () async => done++,
      ),
    );

    final res = await source.request();
    expect(await res.stream.toList(), [<int>[1, 2], <int>[3]]);
    expect(chunks, [<int>[1, 2], <int>[3]]);
    expect(done, 1);
  });

  test('Range 请求（start>0）不写缓存', () async {
    final chunks = <List<int>>[];
    var done = 0;
    final source = CacheStreamAudioSource(
      open: ({int? start, int? end}) async =>
          _resp(Stream.fromIterable([<int>[9]]), length: 1),
      hooks: CacheStreamHooks(
        onBytes: chunks.add,
        onComplete: () async => done++,
      ),
    );

    final res = await source.request(2, 2);
    expect(await res.stream.toList(), [<int>[9]]);
    expect(chunks, isEmpty);
    expect(done, 0);
  });

  test('流出错：onError 被调用且错误透传', () async {
    Object? seen;
    final source = CacheStreamAudioSource(
      open: ({int? start, int? end}) async =>
          _resp(Stream<List<int>>.error(StateError('boom'))),
      hooks: CacheStreamHooks(onError: (e) async => seen = e),
    );

    final res = await source.request();
    await expectLater(res.stream.toList(), throwsStateError);
    expect(seen, isA<StateError>());
  });
}
