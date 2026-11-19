/// A11-M3 接线源：sink 在完/错时 commit/abort；Range 不写；HTTP opener 不在此测（需网络桩）
import 'dart:async';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:player/player.dart';

class _Sink implements AudioCacheStreamSink {
  final chunks = <List<int>>[];
  var committed = 0;
  var aborted = 0;
  @override
  Future<void> add(List<int> bytes) async => chunks.add(bytes);
  @override
  Future<void> commit() async => committed++;
  @override
  Future<void> abort() async => aborted++;
}

StreamAudioResponse _resp(Stream<List<int>> stream) => StreamAudioResponse(
      sourceLength: 4,
      contentLength: 4,
      offset: 0,
      stream: stream,
      contentType: 'audio/mpeg',
    );

void main() {
  test('正常结束：字节写入 sink 并 commit', () async {
    final sink = _Sink();
    final source = CachingStreamAudioSource(
      open: ({int? start, int? end}) async =>
          _resp(Stream.fromIterable([<int>[1, 2], <int>[3, 4]])),
      openSink: () async => sink,
    );
    final res = await source.request();
    expect(await res.stream.toList(), [<int>[1, 2], <int>[3, 4]]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(sink.chunks, [<int>[1, 2], <int>[3, 4]]);
    expect(sink.committed, 1);
    expect(sink.aborted, 0);
  });

  test('流出错：abort，不 commit', () async {
    final sink = _Sink();
    final source = CachingStreamAudioSource(
      open: ({int? start, int? end}) async =>
          _resp(Stream<List<int>>.error(StateError('boom'))),
      openSink: () async => sink,
    );
    final res = await source.request();
    await expectLater(res.stream.toList(), throwsStateError);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(sink.aborted, 1);
    expect(sink.committed, 0);
  });

  test('Range 请求：不打开 sink', () async {
    var opened = 0;
    final source = CachingStreamAudioSource(
      open: ({int? start, int? end}) async => _resp(Stream.fromIterable([<int>[9]])),
      openSink: () async { opened++; return _Sink(); },
    );
    final res = await source.request(2, 2);
    expect(await res.stream.toList(), [<int>[9]]);
    expect(opened, 0);
  });
}
