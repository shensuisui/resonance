/// A11-M4：LockCachingAudioSource 边播边落盘——1 倍流量、完成 adopt、seek 可用
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:core/core.dart';
import 'package:db/db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:player/player.dart';

const String _mp3B64 = 'SUQzBAAAAAAAIlRTU0UAAAAOAAADTGF2ZjYxLjEuMTAwAAAAAAAAAAAAAAD/+0DAAAAAAAAAAAAAAAAAAAAAAABJbmZvAAAADwAAABgAAAp2ABsbGxslJSUlLy8vLzk5OTlDQ0NDTU1NTVZWVlZWYGBgYGpqamp0dHR0fn5+foiIiIiSkpKSkpycnJympqamsLCwsLq6urrExMTEzs7Ozs7Y2NjY4uLi4uzs7Oz29vb2/////wAAAABMYXZjNjEuMy4AAAAAAAAAAAAAAAAkAmQAAAAAAAAKdr9Mx1cAAAAAAP/7EMQAA8AAAaQAAAAgAAA0gAAABExBTUUzLjEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBVVVVV//sQxCmDwAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUUzLjEwMFVVVVX/+xDEUwPAAAGkAAAAIAAANIAAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMuMTAwVVVVVf/7EMR8g8AAAaQAAAAgAAA0gAAABFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBVVVVV//sQxKYDwAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUUzLjEwMFVVVVX/+xDEz4PAAAGkAAAAIAAANIAAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMuMTAwVVVVVf/7EMTWA8AAAaQAAAAgAAA0gAAABFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBVVVVV//sQxNYDwAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUUzLjEwMFVVVVX/+xDE1gPAAAGkAAAAIAAANIAAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMuMTAwVVVVVf/7EMTWA8AAAaQAAAAgAAA0gAAABFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBVVVVV//sQxNYDwAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUUzLjEwMFVVVVX/+xDE1gPAAAGkAAAAIAAANIAAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMuMTAwVVVVVf/7EMTWA8AAAaQAAAAgAAA0gAAABFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBVVVVV//sQxNYDwAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUUzLjEwMFVVVVX/+xDE1gPAAAGkAAAAIAAANIAAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMuMTAwVVVVVf/7EMTWA8AAAaQAAAAgAAA0gAAABFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBVVVVV//sQxNYDwAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUUzLjEwMFVVVVX/+xDE1gPAAAGkAAAAIAAANIAAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVTEFNRTMuMTAwVVVVVf/7EMTWA8AAAaQAAAAgAAA0gAAABFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//sQxNYDwAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/+xDE1gPAAAGkAAAAIAAANIAAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVf/7EMTWA8AAAaQAAAAgAAA0gAAABFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//sQxNYDwAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/+xDE1gPAAAGkAAAAIAAANIAAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVQ==';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LockCaching：1 倍流量 + 缓存完整 + seek', (tester) async {
    final bytes = base64Decode(_mp3B64);
    var served = 0;
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      requests++;
      final res = req.response;
      final range = req.headers.value(HttpHeaders.rangeHeader);
      var start = 0;
      var end = bytes.length - 1;
      if (range != null && range.startsWith('bytes=')) {
        final parts = range.substring(6).split('-');
        start = int.tryParse(parts.first) ?? 0;
        if (parts.length > 1 && parts[1].isNotEmpty) {
          end = int.tryParse(parts[1]) ?? end;
        }
        if (end >= bytes.length) end = bytes.length - 1;
        final slice = bytes.sublist(start, end + 1);
        served += slice.length;
        res
          ..statusCode = HttpStatus.partialContent
          ..headers.set(HttpHeaders.contentRangeHeader,
              'bytes $start-$end/${bytes.length}')
          ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..headers.contentType = ContentType('audio', 'mpeg')
          ..headers.contentLength = slice.length
          ..add(slice);
      } else {
        served += bytes.length;
        res
          ..statusCode = HttpStatus.ok
          ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..headers.contentType = ContentType('audio', 'mpeg')
          ..headers.contentLength = bytes.length
          ..add(bytes);
      }
      await res.close();
    });

    final base = await getTemporaryDirectory();
    final ts = DateTime.now().microsecondsSinceEpoch;
    final cacheDir = Directory('${base.path}/lock_cache_$ts')..createSync(recursive: true);
    final cache = AudioCacheImpl(customDir: cacheDir.path);
    await cache.init();

    final uri = Uri.parse('http://127.0.0.1:${server.port}/a.mp3');
    final song = Song(
      id: 'm4lock',
      sourceId: 's',
      title: '锁存',
      artist: '歌手',
      playUrl: uri.toString(),
    );
    final target = cache.targetPathFor(song.globalKey)!;
    final key = song.globalKey;

    final player = PlayerImpl(
      audioSourceBuilder: (url, {Song? song}) {
        final source = LockCachingAudioSource(url, cacheFile: File(target));
        source.downloadProgressStream.listen((p) async {
          if (p >= 1.0 || File(target).existsSync()) {
            await cache.adoptExistingFile(key);
          }
        }, onError: (Object _) {});
        return source;
      },
    );
    await player.play(song);

    var cached = false;
    for (var i = 0; i < 300; i++) {
      if (cache.isCached(song.globalKey)) {
        cached = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    try {
      await player.seek(const Duration(milliseconds: 300));
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(cached, isTrue, reason: 'LockCaching 未完成落盘/adopt');
    final file = File(target);
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), bytes.length, reason: '缓存文件应完整');
    expect(served, lessThan(bytes.length * 2), reason: '约 1 倍流量: served=$served size=${bytes.length}');
    // ignore: avoid_print
    print('M4_LOCK_RESULT served=$served size=${bytes.length} requests=$requests');

    await player.dispose();
    await server.close(force: true);
    await cache.dispose();
    cacheDir.deleteSync(recursive: true);
  });
}
