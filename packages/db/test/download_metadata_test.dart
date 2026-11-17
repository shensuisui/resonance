/// P3：元信息组装（基础标签 + 256 JPEG85 封面 + LRC 歌词 + warning）
import 'dart:convert';
import 'dart:io';
import 'package:audiotags/audiotags.dart';
import 'package:core/core.dart';
import 'package:db/db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

class _FakeWriter implements TagWriter {
  Tag? last;
  String? lastPath;
  bool throwOnWrite = false;
  @override
  Future<void> write(String path, Tag tag) async {
    lastPath = path;
    last = tag;
    if (throwOnWrite) throw StateError('boom');
  }
}

late List<int> _coverJpg;
late _FakeWriter _writer;

Future<HttpServer> _server() async {
  final s = await HttpServer.bind('localhost', 0);
  s.listen((req) {
    if (req.uri.path == '/cover.jpg') {
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType('image', 'jpeg')
        ..contentLength = _coverJpg.length
        ..add(_coverJpg)
        ..close();
    } else if (req.uri.path == '/a.wav') {
      final b = utf8.encode('RIFF....WAVEfake');
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType('audio', 'wav')
        ..contentLength = b.length
        ..add(b)
        ..close();
    } else if (req.uri.path == '/a.mp3') {
      final b = utf8.encode('ID3fake_audio_body_bytes');
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType('audio', 'mpeg')
        ..contentLength = b.length
        ..add(b)
        ..close();
    } else {
      req.response
        ..statusCode = 404
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

  setUpAll(() {
    _coverJpg = img.encodeJpg(img.Image(width: 8, height: 8), quality: 90);
  });

  setUp(() async {
    initSqfliteForPlatform();
    provider = SqfliteDatabaseProvider.withHelper(
        DatabaseHelper(customDbPath: getInMemoryDatabasePath()));
    await provider.initialize();
    server = await _server();
    dir = await Directory.systemTemp.createTemp('resonance_meta_');
    _writer = _FakeWriter();
    dm = DownloadManagerImpl(
      songDao: provider.songDao,
      downloadTaskDao: provider.downloadTaskDao,
      customCacheDir: dir.path,
      tagWriter: _writer,
    );
  });

  tearDown(() async {
    dm.dispose();
    await server.close();
    await provider.close();
    await dir.delete(recursive: true);
  });

  test('写入标题/歌手/专辑/歌词/封面（256 JPEG）', () async {
    final song = Song(
      id: 'm1',
      sourceId: 's',
      title: '标签歌',
      artist: '歌手',
      album: '专辑',
      coverUrl: 'http://localhost:${server.port}/cover.jpg',
      playUrl: 'http://localhost:${server.port}/a.mp3',
    );
    await dm.download(song, lyrics: '[00:01.00]第一句');
    final t = await _wait(dm, song.globalKey);
    expect(t!.status, DownloadStatus.completed);
    expect(t.warning, isNull, reason: '不应有 warning: ${t.warning}');

    final tag = _writer.last!;
    expect(tag.title, '标签歌');
    expect(tag.trackArtist, '歌手');
    expect(tag.album, '专辑');
    expect(tag.lyrics, contains('第一句'));
    expect(tag.pictures.length, 1);
    expect(tag.pictures.first.mimeType, MimeType.jpeg);
    final decoded = img.decodeImage(tag.pictures.first.bytes);
    expect(decoded!.width, 256);
    expect(decoded.height, 256);
    expect(_writer.lastPath, t.localPath);
  });

  test('封面 404 → 下载仍成功，warning 标记封面失败', () async {
    final song = Song(
      id: 'm2',
      sourceId: 's',
      title: '无封面',
      artist: '歌手',
      coverUrl: 'http://localhost:${server.port}/missing.jpg',
      playUrl: 'http://localhost:${server.port}/a.mp3',
    );
    await dm.download(song, lyrics: '[00:01.00]词');
    final t = await _wait(dm, song.globalKey);
    expect(t!.status, DownloadStatus.completed);
    expect(t.warning, contains('封面'));
    expect(_writer.last!.pictures, isEmpty);
    expect(_writer.last!.title, '无封面');
  });

  test('不支持格式（wav）→ 下载成功但 warning 提示不写标签', () async {
    final song = Song(
      id: 'm3',
      sourceId: 's',
      title: '波形',
      artist: '歌手',
      playUrl: 'http://localhost:${server.port}/a.wav',
    );
    await dm.download(song);
    final t = await _wait(dm, song.globalKey);
    expect(t!.status, DownloadStatus.completed);
    expect(t.warning, contains('不支持'));
    expect(_writer.last, isNull, reason: '不支持格式不应调用写入');
  });

  test('标签写入抛错 → 下载仍成功，warning 标记写入失败', () async {
    _writer.throwOnWrite = true;
    final song = Song(
      id: 'm4',
      sourceId: 's',
      title: '写失败',
      artist: '歌手',
      playUrl: 'http://localhost:${server.port}/a.mp3',
    );
    await dm.download(song, lyrics: '[00:01.00]词');
    final t = await _wait(dm, song.globalKey);
    expect(t!.status, DownloadStatus.completed);
    expect(t.warning, contains('标签写入失败'));
  });
}
