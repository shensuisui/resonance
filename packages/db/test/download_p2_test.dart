/// P2 下载实现行为测试：命名/去重/headers/扩展名/removeRecord
import 'dart:convert';
import 'dart:io';
import 'package:core/core.dart';
import 'package:db/db.dart';
import 'package:flutter_test/flutter_test.dart';

class _Recorder {
  String? referer;
}

Future<HttpServer> _server(_Recorder rec) async {
  final s = await HttpServer.bind('localhost', 0);
  s.listen((req) {
    rec.referer = req.headers.value('referer');
    if (req.uri.path == '/noext') {
      final bytes = utf8.encode('fLaC000000000000');
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType('audio', 'flac')
        ..contentLength = bytes.length
        ..add(bytes)
        ..close();
    } else {
      final bytes = utf8.encode('ID3fake_audio_bytes_for_test');
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType('audio', 'mpeg')
        ..contentLength = bytes.length
        ..add(bytes)
        ..close();
    }
  });
  return s;
}

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
  late Directory dir;
  late DownloadManagerImpl dm;
  late _Recorder rec;

  setUp(() async {
    provider = SqfliteDatabaseProvider.withHelper(
        DatabaseHelper(customDbPath: getInMemoryDatabasePath()));
    initSqfliteForPlatform();
    await provider.initialize();
    rec = _Recorder();
    server = await _server(rec);
    dir = await Directory.systemTemp.createTemp('resonance_p2_');
    dm = DownloadManagerImpl(
      songDao: provider.songDao,
      downloadTaskDao: provider.downloadTaskDao,
      customCacheDir: dir.path,
    );
  });

  tearDown(() async {
    dm.dispose();
    await server.close();
    await provider.close();
    await dir.delete(recursive: true);
  });

  test('完成后是可读文件名（歌手 - 歌曲），且无 .part 残留', () async {
    final song = Song(
      id: 'n1',
      sourceId: 's',
      title: '晴天',
      artist: '周杰伦',
      playUrl: 'http://localhost:${server.port}/a.mp3',
    );
    await dm.download(song);
    final t = await _wait(dm, song.globalKey);
    expect(t!.status, DownloadStatus.completed);
    final base = t.localPath!.split(Platform.pathSeparator).last;
    expect(base, '周杰伦 - 晴天.mp3');
    final parts = Directory(dir.path).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.part'));
    expect(parts, isEmpty);
  });

  test('同曲重复下载不产生第二个文件/并发', () async {
    final song = Song(
      id: 'n2',
      sourceId: 's',
      title: '去重',
      artist: '手',
      playUrl: 'http://localhost:${server.port}/a.mp3',
    );
    await dm.download(song);
    await dm.download(song);
    final t = await _wait(dm, song.globalKey);
    expect(t!.status, DownloadStatus.completed);
    final files = Directory(dir.path).listSync(recursive: true).whereType<File>().toList();
    expect(files.where((f) => f.path.endsWith('.mp3')).length, 1);
  });

  test('headers 透传到请求', () async {
    final song = Song(
      id: 'n3',
      sourceId: 's',
      title: '头',
      artist: '手',
      playUrl: 'http://localhost:${server.port}/a.mp3',
    );
    await dm.download(song, headers: {'referer': 'https://example.com/'});
    final t = await _wait(dm, song.globalKey);
    expect(t!.status, DownloadStatus.completed);
    expect(rec.referer, 'https://example.com/');
  });

  test('无扩展名 URL 用 Content-Type 推断（flac）', () async {
    final song = Song(
      id: 'n4',
      sourceId: 's',
      title: '格式',
      artist: '手',
      playUrl: 'http://localhost:${server.port}/noext',
    );
    await dm.download(song);
    final t = await _wait(dm, song.globalKey);
    expect(t!.localPath!.endsWith('.flac'), isTrue);
  });

  test('removeRecord 只清 failed/cancelled 记录', () async {
    final bad = Song(id: 'n5', sourceId: 's', title: '无地址', artist: '手');
    await dm.download(bad);
    final t = await _wait(dm, bad.globalKey);
    expect(t!.status, DownloadStatus.failed);
    await dm.removeRecord(bad.globalKey);
    expect(dm.getTasks().any((x) => x.songKey == bad.globalKey), isFalse);

    final good = Song(
      id: 'n6',
      sourceId: 's',
      title: '成品',
      artist: '手',
      playUrl: 'http://localhost:${server.port}/a.mp3',
    );
    await dm.download(good);
    await _wait(dm, good.globalKey);
    await dm.removeRecord(good.globalKey);
    expect(dm.getTasks().any((x) => x.songKey == good.globalKey), isTrue,
        reason: 'completed 不允许 removeRecord');
  });
}
