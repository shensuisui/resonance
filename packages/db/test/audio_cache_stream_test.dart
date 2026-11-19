/// A11-M3 接线：AudioCache 流式写入（.part → commit 入索引 / abort / clear 中断）
import 'dart:io';
import 'package:core/core.dart';
import 'package:db/db.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  const song = Song(id: 'stream1', sourceId: 's', title: '流', artist: '手');

  setUp(() async { tmp = await Directory.systemTemp.createTemp('cache_stream_'); });
  tearDown(() async { if (await tmp.exists()) await tmp.delete(recursive: true); });

  test('add + commit：完整文件入索引，无 .part 残留', () async {
    final cache = AudioCacheImpl(customDir: tmp.path);
    await cache.init();
    final sink = await cache.openStream(song.globalKey);
    await sink.add([1, 2, 3]);
    await sink.add([4, 5]);
    await sink.commit();

    expect(cache.isCached(song.globalKey), isTrue);
    final file = File(cache.filePathFor(song.globalKey)!);
    expect(await file.readAsBytes(), [1, 2, 3, 4, 5]);
    final parts = tmp.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.part'));
    expect(parts, isEmpty);
    await cache.dispose();
  });

  test('abort：删 .part，不写索引', () async {
    final cache = AudioCacheImpl(customDir: tmp.path);
    await cache.init();
    final sink = await cache.openStream(song.globalKey);
    await sink.add([1, 2]);
    await sink.abort();
    expect(cache.isCached(song.globalKey), isFalse);
    final files = tmp.listSync(recursive: true).whereType<File>().toList();
    expect(files, isEmpty);
    await cache.dispose();
  });

  test('clear 中断：commit 被代际拦截，不留文件/索引', () async {
    final cache = AudioCacheImpl(customDir: tmp.path);
    await cache.init();
    final sink = await cache.openStream(song.globalKey);
    await sink.add([1, 2, 3]);
    await cache.clear();
    await sink.commit();
    expect(cache.isCached(song.globalKey), isFalse);
    final files = tmp.listSync(recursive: true).whereType<File>().toList();
    expect(files, isEmpty);
    await cache.dispose();
  });
}
