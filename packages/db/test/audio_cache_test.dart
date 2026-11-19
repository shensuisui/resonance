/// AudioCacheImpl 测试
///
/// 用真实本地 HTTP 服务器 + 真实文件 IO（不 mock）。锁定「乙」引擎的硬要求：
///   1. 起播后另存一份，且**完整文件**才进索引、才给出 file:// 地址；
///   2. 只有 .part 残片（或 0 字节）时**不算命中**（绝不播半截文件）；
///   3. 已下载（localPath 存在）的歌不再另存一份；
///   4. 下载失败静默：不写缓存、不抛异常；
///   5. 清空后索引与磁盘都干净；新增时会通知 UI。
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:db/db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late HttpServer server;
  late int port;
  late Directory tmp;

  /// 被测曲目（规则源快照：没有播放地址、没有本地文件）
  const song = Song(id: 'abc', sourceId: '6uq', title: '标题', artist: '歌手');

  setUp(() async {
    server = await HttpServer.bind('localhost', 0);
    port = server.port;
    tmp = await Directory.systemTemp.createTemp('audio_cache_test');
    server.listen((request) async {
      final res = request.response;
      if (request.uri.path == '/slow.mp3') {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final bytes = List<int>.filled(4096, 8);
        res
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.binary
          ..contentLength = bytes.length
          ..add(bytes);
      } else if (request.uri.path == '/audio.mp3') {
        final bytes = List<int>.filled(4096, 7);
        res
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.binary
          ..contentLength = bytes.length
          ..add(bytes);
      } else {
        res.statusCode = HttpStatus.notFound;
      }
      await res.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('起播后缓存一份：完整文件才进索引，并给出可用的 file:// 地址', () async {
    final cache = AudioCacheImpl(customDir: tmp.path);
    await cache.init();
    expect(cache.isCached(song.globalKey), isFalse);
    expect(cache.localUrlFor(song.globalKey), isNull);

    await cache.cacheAfterPlay(song, 'http://localhost:$port/audio.mp3');

    expect(cache.isCached(song.globalKey), isTrue);
    final url = cache.localUrlFor(song.globalKey);
    expect(url, startsWith('file:'));
    expect(await File.fromUri(Uri.parse(url!)).length(), 4096);
    expect(await cache.sizeOnDisk(), 4096);
    await cache.dispose();
  });

  test('初始化索引：只有 .part 残片（或 0 字节文件）时不算命中', () async {
    final cache = AudioCacheImpl(customDir: tmp.path);
    await cache.init();
    final target = cache.debugPathFor(song.globalKey)!;
    await File(target).parent.create(recursive: true);
    // 模拟"上次下到一半"：只有残片
    await File('$target.part').writeAsBytes(List<int>.filled(1024, 1));
    await cache.rescan();
    expect(cache.isCached(song.globalKey), isFalse, reason: '半截文件绝不能命中');

    // 完整文件到位后（残片仍在）应命中
    await File(target).writeAsBytes(List<int>.filled(2048, 2));
    await cache.rescan();
    expect(cache.isCached(song.globalKey), isTrue);
    expect(cache.localUrlFor(song.globalKey), startsWith('file:'));
    await cache.dispose();
  });

  test('已下载（localPath 存在）的歌不再另存一份', () async {
    final otherDir = await Directory.systemTemp.createTemp('downloaded');
    final localFile = File(p.join(otherDir.path, 'downloaded.mp3'));
    await localFile.writeAsBytes(List<int>.filled(10, 3));

    final cache = AudioCacheImpl(customDir: tmp.path);
    await cache.init();
    await cache.cacheAfterPlay(
      song.copyWith(localPath: localFile.path),
      'http://localhost:$port/audio.mp3',
    );

    expect(cache.isCached(song.globalKey), isFalse, reason: '已有下载文件就不该再占一份');
    await cache.dispose();
    await otherDir.delete(recursive: true);
  });

  test('下载失败（404）静默：不写缓存、不抛异常', () async {
    final cache = AudioCacheImpl(customDir: tmp.path);
    await cache.init();

    await cache.cacheAfterPlay(song, 'http://localhost:$port/missing.mp3');

    expect(cache.isCached(song.globalKey), isFalse);
    expect(cache.localUrlFor(song.globalKey), isNull);
    await cache.dispose();
  });

  test('清空后索引与磁盘都干净；新增/清空都会通知 UI', () async {
    final cache = AudioCacheImpl(customDir: tmp.path);
    await cache.init();
    final events = <int>[];
    final sub = cache.changes.listen((_) => events.add(events.length));

    await cache.cacheAfterPlay(song, 'http://localhost:$port/audio.mp3');
    expect(await cache.sizeOnDisk(), greaterThan(0));

    await cache.clear();
    expect(cache.isCached(song.globalKey), isFalse);
    expect(await cache.sizeOnDisk(), 0);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(events.length, 2, reason: '新增一次 + 清空一次');

    await sub.cancel();
    await cache.dispose();
  });

  test('同一首并发只下一次（去重）', () async {
    final cache = AudioCacheImpl(customDir: tmp.path);
    await cache.init();
    await Future.wait([
      cache.cacheAfterPlay(song, 'http://localhost:$port/audio.mp3'),
      cache.cacheAfterPlay(song, 'http://localhost:$port/audio.mp3'),
    ]);
    expect(cache.isCached(song.globalKey), isTrue);
    expect(cache.cachedKeys.length, 1);
    await cache.dispose();
  });

  test('外部删除文件后 isCached/localUrlFor 自愈', () async {
    final cache = AudioCacheImpl(customDir: tmp.path);
    await cache.init();
    await cache.cacheAfterPlay(song, 'http://localhost:$port/audio.mp3');
    expect(cache.isCached(song.globalKey), isTrue);

    final path = cache.filePathFor(song.globalKey)!;
    await File(path).delete();

    expect(cache.isCached(song.globalKey), isFalse);
    expect(cache.localUrlFor(song.globalKey), isNull);
    expect(cache.cachedKeys, isEmpty);
    await cache.dispose();
  });

  test('init 幂等：重复调用只扫盘/广播一次', () async {
    final cache = AudioCacheImpl(customDir: tmp.path);
    var events = 0;
    final sub = cache.changes.listen((_) => events++);
    await cache.init();
    await cache.init();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(events, 1);
    await sub.cancel();
    await cache.dispose();
  });

  test('clear 取消在飞下载，且不再写回索引/文件', () async {
    final cache = AudioCacheImpl(customDir: tmp.path);
    await cache.init();
    final future = cache.cacheAfterPlay(song, 'http://localhost:$port/slow.mp3');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await cache.clear();
    await future;
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(cache.isCached(song.globalKey), isFalse);
    final leftovers = tmp
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.mp3') || f.path.endsWith('.part'))
        .toList();
    expect(leftovers, isEmpty);
    await cache.dispose();
  });
}
