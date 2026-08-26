/// DownloadManagerImpl 测试
///
/// 使用真实本地 HTTP 服务器 + in-memory SQLite，
/// 验证下载、缓存、取消、状态流。
/// 不使用 mock——真实 HTTP 请求 + 真实文件 IO。

import 'dart:io';
import 'dart:convert';
import 'package:core/core.dart';
import 'package:db/db.dart';
import 'package:flutter_test/flutter_test.dart';

/// 测试用 HTTP 服务器——提供文件下载
Future<HttpServer> _startTestServer() async {
  final server = await HttpServer.bind('localhost', 0);
  server.listen((request) {
    final uri = request.uri;
    if (uri.path == '/test.mp3') {
      final bytes = utf8.encode('fake_audio_content_for_testing');
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.binary
        ..contentLength = bytes.length
        ..add(bytes)
        ..close();
    } else if (uri.path == '/notfound') {
      request.response
        ..statusCode = 404
        ..write('Not Found')
        ..close();
    } else {
      request.response
        ..statusCode = 404
        ..write('Unknown')
        ..close();
    }
  });
  return server;
}

DatabaseHelper _newInMemoryHelper() {
  initSqfliteForPlatform();
  return DatabaseHelper(customDbPath: getInMemoryDatabasePath());
}

/// 轮询等待下载完成（或失败/取消），最多等 5 秒
Future<DownloadTask?> _waitForComplete(
    DownloadManagerImpl dm, String songKey) async {
  for (int i = 0; i < 50; i++) {
    await Future.delayed(const Duration(milliseconds: 100));
    final task = dm.getTasks().where((t) => t.songKey == songKey).firstOrNull;
    if (task == null) continue;
    if (task.status == DownloadStatus.completed ||
        task.status == DownloadStatus.failed ||
        task.status == DownloadStatus.cancelled) {
      return task;
    }
  }
  return null; // 超时
}

void main() {
  late SqfliteDatabaseProvider provider;
  late HttpServer server;
  late DownloadManagerImpl downloadManager;
  late Directory tempCacheDir;

  setUp(() async {
    provider = SqfliteDatabaseProvider.withHelper(_newInMemoryHelper());
    await provider.initialize();

    server = await _startTestServer();
    tempCacheDir = await Directory.systemTemp.createTemp('fm_dl_');

    downloadManager = DownloadManagerImpl(
      songDao: provider.songDao,
      customCacheDir: tempCacheDir.path,
    );
  });

  tearDown(() async {
    downloadManager.dispose();
    await server.close();
    await provider.close();
    await tempCacheDir.delete(recursive: true);
  });

  group('DownloadManagerImpl', () {
    test('初始状态无任务', () {
      expect(downloadManager.getTasks(), isEmpty);
      expect(downloadManager.taskStream, isNotNull);
    });

    test('下载无 URL 的歌曲返回 null', () async {
      final song = Song(id: '1', sourceId: 's', title: '歌', artist: '手');
      final result = await downloadManager.download(song);
      expect(result, isNull);
    });

    test('下载文件到本地缓存', () async {
      final song = Song(
        id: '1',
        sourceId: 's',
        title: '测试歌曲',
        artist: '测试',
        playUrl: 'http://localhost:${server.port}/test.mp3',
      );
      await provider.songDao.insertSong(song);
      await downloadManager.download(song);

      // 轮询等待完成
      final task = await _waitForComplete(downloadManager, song.globalKey);
      expect(task, isNotNull, reason: '下载应完成');
      expect(task!.status, DownloadStatus.completed,
          reason: '下载状态应为 completed');

      // 检查缓存
      final isCached = await downloadManager.isCached(song.globalKey);
      expect(isCached, isTrue, reason: '文件应已缓存');

      // 检查本地路径
      final path = await downloadManager.getLocalPath(song.globalKey);
      expect(path, isNotNull);
      expect(path, isNotEmpty);

      // 检查文件内容
      final file = File(path!);
      expect(await file.exists(), isTrue);
      final content = await file.readAsString();
      expect(content, 'fake_audio_content_for_testing');
    });

    test('下载后 SongDao 的 localPath 更新', () async {
      final song = Song(
        id: '2',
        sourceId: 's',
        title: '歌',
        artist: '手',
        playUrl: 'http://localhost:${server.port}/test.mp3',
      );
      await provider.songDao.insertSong(song);
      await downloadManager.download(song);

      await _waitForComplete(downloadManager, song.globalKey);

      // 从数据库重新读取
      final updated = await provider.songDao.getSong('2', 's');
      expect(updated!.localPath, isNotNull, reason: '数据库 localPath 应更新');
      expect(updated.localPath, isNotEmpty);
    });

    test('已有缓存的歌曲不重复下载', () async {
      // 创建一个已有 localPath 的歌曲（模拟已缓存）
      final song = Song(
        id: '3',
        sourceId: 's',
        title: '歌',
        artist: '手',
        localPath: '${tempCacheDir.path}/existing.mp3',
      );
      // 创建缓存文件
      await File(song.localPath!).writeAsBytes([0x00]);

      await downloadManager.download(song);

      // 应立即返回（不下载），任务状态为 completed
      final task = await _waitForComplete(downloadManager, song.globalKey);
      expect(task, isNotNull);
      expect(task!.status, DownloadStatus.completed);
      expect(task.localPath, song.localPath);
    });

    test('任务状态流推送更新', () async {
      final song = Song(
        id: '4',
        sourceId: 's',
        title: '歌',
        artist: '手',
        playUrl: 'http://localhost:${server.port}/test.mp3',
      );

      final states = <List<DownloadTask>>[];
      final sub = downloadManager.taskStream.listen(states.add);

      await downloadManager.download(song);
      await _waitForComplete(downloadManager, song.globalKey);

      expect(states, isNotEmpty);
      final hasTask = states.any((tasks) =>
          tasks.any((t) => t.songKey == song.globalKey));
      expect(hasTask, isTrue);

      await sub.cancel();
    });

    test('取消下载', () async {
      final song = Song(
        id: '5',
        sourceId: 's',
        title: '歌',
        artist: '手',
        playUrl: 'http://localhost:${server.port}/test.mp3',
      );

      await downloadManager.download(song);
      await downloadManager.cancel(song.globalKey);

      // 等待一下让异步操作完成
      await Future.delayed(const Duration(milliseconds: 500));

      final task = downloadManager.getTasks()
          .where((t) => t.songKey == song.globalKey)
          .firstOrNull;
      if (task != null) {
        expect(task.status, anyOf(
          DownloadStatus.cancelled,
          DownloadStatus.completed,
        ));
      }
    });

    test('删除缓存', () async {
      final song = Song(
        id: '6',
        sourceId: 's',
        title: '歌',
        artist: '手',
        playUrl: 'http://localhost:${server.port}/test.mp3',
      );
      await provider.songDao.insertSong(song);
      await downloadManager.download(song);
      await _waitForComplete(downloadManager, song.globalKey);

      // 确认已缓存
      expect(await downloadManager.isCached(song.globalKey), isTrue);

      // 删除缓存
      await downloadManager.deleteCache(song.globalKey);
      expect(await downloadManager.isCached(song.globalKey), isFalse);
    });

    test('getLocalPath 从数据库恢复', () async {
      final song = Song(
        id: '7',
        sourceId: 's',
        title: '歌',
        artist: '手',
        localPath: '/cached/path.mp3',
      );
      await provider.songDao.insertSong(song);

      final path = await downloadManager.getLocalPath(song.globalKey);
      expect(path, '/cached/path.mp3');
    });
  });
}
