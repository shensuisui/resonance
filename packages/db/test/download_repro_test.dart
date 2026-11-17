/// 下载功能 P0 复现测试（当前实现应失败，作为修复前的证据）
///
/// 目标行为：
/// 1) deleteCache 必须清掉 songs.local_path；
/// 2) 未 insert 的歌曲下载后，songs 表应存在该行且 local_path 非空；
/// 3) 新实例（模拟重启）应能加载已完成的下载任务。
import 'dart:io';
import 'dart:convert';
import 'package:core/core.dart';
import 'package:db/db.dart';
import 'package:flutter_test/flutter_test.dart';

Future<HttpServer> _startServer() async {
  final server = await HttpServer.bind('localhost', 0);
  server.listen((request) {
    if (request.uri.path == '/test.mp3') {
      final bytes = utf8.encode('fake_audio_content_for_testing');
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.binary
        ..contentLength = bytes.length
        ..add(bytes)
        ..close();
    } else {
      request.response
        ..statusCode = 404
        ..close();
    }
  });
  return server;
}

DatabaseHelper _helper() {
  initSqfliteForPlatform();
  return DatabaseHelper(customDbPath: getInMemoryDatabasePath());
}

Future<DownloadTask?> _wait(DownloadManager dm, String key) async {
  for (var i = 0; i < 50; i++) {
    await Future.delayed(const Duration(milliseconds: 100));
    final t = dm.getTasks().where((x) => x.songKey == key).firstOrNull;
    if (t == null) continue;
    if (t.status == DownloadStatus.completed ||
        t.status == DownloadStatus.failed ||
        t.status == DownloadStatus.cancelled) {
      return t;
    }
  }
  return null;
}

void main() {
  late SqfliteDatabaseProvider provider;
  late HttpServer server;
  late Directory dir;
  late DownloadManagerImpl dm;

  setUp(() async {
    provider = SqfliteDatabaseProvider.withHelper(_helper());
    await provider.initialize();
    server = await _startServer();
    dir = await Directory.systemTemp.createTemp('resonance_p0_');
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

  group('P0 复现（修复前应失败）', () {
    test('deleteCache 应清除 songs.local_path', () async {
      final song = Song(
        id: 'p0a',
        sourceId: 's',
        title: '歌',
        artist: '手',
        playUrl: 'http://localhost:' + server.port.toString() + '/test.mp3',
      );
      await provider.songDao.insertSong(song);
      await dm.download(song);
      await _wait(dm, song.globalKey);

      final afterDownload = await provider.songDao.getSong('p0a', 's');
      expect(afterDownload!.localPath, isNotNull, reason: '前置：下载应写入 local_path');

      await dm.deleteCache(song.globalKey);

      final afterDelete = await provider.songDao.getSong('p0a', 's');
      expect(afterDelete!.localPath, isNull, reason: '删除缓存后 local_path 必须清空');
    });

    test('未 insert 的歌曲下载后 songs 表应有该行且 local_path 非空', () async {
      final song = Song(
        id: 'p0b',
        sourceId: 's',
        title: '新歌',
        artist: '手',
        playUrl: 'http://localhost:' + server.port.toString() + '/test.mp3',
      );
      // 故意不 insertSong，模拟“从未播放过、元数据服务也没写过”的歌
      await dm.download(song);
      await _wait(dm, song.globalKey);

      final stored = await provider.songDao.getSong('p0b', 's');
      expect(stored, isNotNull, reason: '下载应 upsert songs 行');
      expect(stored!.localPath, isNotNull, reason: 'local_path 应落库');
    });

    test('新实例（模拟重启）应能加载已完成的下载任务', () async {
      final song = Song(
        id: 'p0c',
        sourceId: 's',
        title: '重启',
        artist: '手',
        playUrl: 'http://localhost:' + server.port.toString() + '/test.mp3',
      );
      await provider.songDao.insertSong(song);
      await dm.download(song);
      await _wait(dm, song.globalKey);

      final restarted = DownloadManagerImpl(
        songDao: provider.songDao,
        downloadTaskDao: provider.downloadTaskDao,
        customCacheDir: dir.path,
      );
      await restarted.init();
      addTearDown(restarted.dispose);

      final tasks = restarted.getTasks();
      expect(tasks.any((t) => t.songKey == song.globalKey), isTrue,
          reason: '重启后应能从 DB 加载已完成任务');
    });
  });
}
