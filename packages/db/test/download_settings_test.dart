/// P4 后端：命名顺序/封面尺寸/质量 从 settings 读取并生效
import 'dart:convert';
import 'dart:io';
import 'package:audiotags/audiotags.dart';
import 'package:core/core.dart';
import 'package:db/db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

class _FakeWriter implements TagWriter {
  Tag? last;
  @override
  Future<void> write(String path, Tag tag) async => last = tag;
}

late List<int> _coverJpg;

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
    } else {
      final b = utf8.encode('ID3fake_audio_body');
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType('audio', 'mpeg')
        ..contentLength = b.length
        ..add(b)
        ..close();
    }
  });
  return s;
}

Future<DownloadTask?> _wait(DownloadManager dm, String key) async {
  for (var i = 0; i < 50; i++) {
    await Future.delayed(const Duration(milliseconds: 100));
    final t = dm.getTasks().where((x) => x.songKey == key).firstOrNull;
    if (t != null && t.status == DownloadStatus.completed) return t;
    if (t != null && t.status == DownloadStatus.failed) return t;
  }
  return null;
}

void main() {
  late SqfliteDatabaseProvider provider;
  late HttpServer server;
  late Directory dir;
  late DownloadManagerImpl dm;
  late _FakeWriter writer;

  setUpAll(() { _coverJpg = img.encodeJpg(img.Image(width: 64, height: 64), quality: 90); });

  setUp(() async {
    initSqfliteForPlatform();
    dir = await Directory.systemTemp.createTemp('resonance_set_');
    provider = SqfliteDatabaseProvider.withHelper(
        DatabaseHelper(customDbPath: '${dir.path}/test.db'));
    await provider.initialize();
    server = await _server();
    writer = _FakeWriter();
    dm = DownloadManagerImpl(
      songDao: provider.songDao,
      downloadTaskDao: provider.downloadTaskDao,
      customCacheDir: dir.path,
      tagWriter: writer,
      settingsDao: provider.settingsDao,
    );
  });

  tearDown(() async {
    dm.dispose();
    await server.close();
    await provider.close();
    await dir.delete(recursive: true);
  });

  test('settings 控制命名顺序与封面尺寸/质量', () async {
    await provider.settingsDao.set(DownloadSettingsKeys.nameOrder, 'title_artist');
    await provider.settingsDao.set(DownloadSettingsKeys.coverSize, '128');
    await provider.settingsDao.set(DownloadSettingsKeys.coverQuality, '90');

    final song = Song(
      id: 's1',
      sourceId: 's',
      title: '歌',
      artist: '手',
      coverUrl: 'http://localhost:${server.port}/cover.jpg',
      playUrl: 'http://localhost:${server.port}/a.mp3',
    );
    await dm.download(song, lyrics: '[00:01.00]词');
    final t = await _wait(dm, song.globalKey);
    expect(t!.status, DownloadStatus.completed);
    expect(t.localPath!.split(Platform.pathSeparator).last, '歌 - 手.mp3');
    final pic = writer.last!.pictures.single;
    final decoded = img.decodeImage(pic.bytes);
    expect(decoded!.width, 128);
    expect(decoded.height, 128);
  });
}
