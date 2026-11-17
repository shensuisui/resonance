/// P2b：缓存命中 → 拷贝为下载文件（不联网）、拷后删缓存；magic 不通过则回退下载
import 'dart:convert';
import 'dart:io';
import 'package:core/core.dart';
import 'package:db/db.dart';
import 'package:flutter_test/flutter_test.dart';

class _Rec { int hits = 0; }

Future<HttpServer> _server(_Rec rec) async {
  final s = await HttpServer.bind('localhost', 0);
  s.listen((req) {
    rec.hits++;
    final bytes = utf8.encode('ID3network_audio_bytes_here');
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType('audio', 'mpeg')
      ..contentLength = bytes.length
      ..add(bytes)
      ..close();
  });
  return s;
}

String _cacheFileName(String songKey) =>
    '${base64Url.encode(utf8.encode(songKey)).replaceAll('=', '')}.mp3';

Future<DownloadTask?> _wait(DownloadManager dm, String key) async {
  for (var i = 0; i < 50; i++) {
    await Future.delayed(const Duration(milliseconds: 100));
    final t = dm.getTasks().where((x) => x.songKey == key).firstOrNull;
    if (t == null) continue;
    if (t.status == DownloadStatus.completed ||
        t.status == DownloadStatus.failed ||
        t.status == DownloadStatus.cancelled) return t;
  }
  return null;
}

void main() {
  late SqfliteDatabaseProvider provider;
  late HttpServer server;
  late Directory cacheDir;
  late Directory dlDir;
  late AudioCacheImpl cache;
  late DownloadManagerImpl dm;
  late _Rec rec;

  setUp(() async {
    initSqfliteForPlatform();
    provider = SqfliteDatabaseProvider.withHelper(
        DatabaseHelper(customDbPath: getInMemoryDatabasePath()));
    await provider.initialize();
    rec = _Rec();
    server = await _server(rec);
    cacheDir = await Directory.systemTemp.createTemp('resonance_cache_');
    dlDir = await Directory.systemTemp.createTemp('resonance_dl2_');
    cache = AudioCacheImpl(customDir: cacheDir.path);
    dm = DownloadManagerImpl(
      songDao: provider.songDao,
      downloadTaskDao: provider.downloadTaskDao,
      audioCache: cache,
      customCacheDir: dlDir.path,
    );
  });

  tearDown(() async {
    dm.dispose();
    await cache.dispose();
    await server.close();
    await provider.close();
    await cacheDir.delete(recursive: true);
    await dlDir.delete(recursive: true);
  });

  test('缓存命中：拷贝为可读下载文件、不联网、拷后删缓存', () async {
    const song = Song(id: 'c1', sourceId: 's', title: '缓存歌', artist: '手');
    final key = song.globalKey;
    final cacheFile = File('${cacheDir.path}${Platform.pathSeparator}s${Platform.pathSeparator}${_cacheFileName(key)}');
    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsString('ID3cached_bytes_abcdef');
    await cache.init();
    expect(cache.isCached(key), isTrue);

    await dm.download(song);
    final t = await _wait(dm, key);
    expect(t!.status, DownloadStatus.completed);
    expect(rec.hits, 0, reason: '缓存命中不应联网');
    expect(t.localPath!.split(Platform.pathSeparator).last, '手 - 缓存歌.mp3');
    expect(await File(t.localPath!).readAsString(), 'ID3cached_bytes_abcdef');
    expect(cache.filePathFor(key), isNull, reason: '拷贝后缓存应删除');
    expect(await cacheFile.exists(), isFalse);
  });

  test('magic 不通过：不拷贝，回退联网下载', () async {
    final song = Song(
      id: 'c2', sourceId: 's', title: '坏缓存', artist: '手',
      playUrl: 'http://localhost:${server.port}/a.mp3',
    );
    final key = song.globalKey;
    final cacheFile = File('${cacheDir.path}${Platform.pathSeparator}s${Platform.pathSeparator}${_cacheFileName(key)}');
    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsString('this_is_not_audio');
    await cache.init();
    expect(cache.isCached(key), isTrue);

    await dm.download(song);
    final t = await _wait(dm, key);
    expect(t!.status, DownloadStatus.completed);
    expect(rec.hits, greaterThan(0), reason: 'magic 不通过应走网络');
    expect(await cacheFile.exists(), isTrue, reason: '未拷贝则缓存保留');
  });
}
