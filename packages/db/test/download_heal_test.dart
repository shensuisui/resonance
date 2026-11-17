/// P5：已下载文件被外部删除 → isCached 自愈（清 local_path + 删任务行）
import 'dart:io';
import 'package:core/core.dart';
import 'package:db/db.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SqfliteDatabaseProvider provider;
  late DownloadManagerImpl dm;
  late Directory dir;

  setUp(() async {
    initSqfliteForPlatform();
    provider = SqfliteDatabaseProvider.withHelper(
        DatabaseHelper(customDbPath: getInMemoryDatabasePath()));
    await provider.initialize();
    dir = await Directory.systemTemp.createTemp('resonance_heal_');
    dm = DownloadManagerImpl(
      songDao: provider.songDao,
      downloadTaskDao: provider.downloadTaskDao,
      customCacheDir: dir.path,
    );
  });

  tearDown(() async {
    dm.dispose();
    await provider.close();
    await dir.delete(recursive: true);
  });

  test('文件被外部删除后 isCached=false 且 local_path 被清空', () async {
    final missing = '${dir.path}${Platform.pathSeparator}s${Platform.pathSeparator}gone.mp3';
    final song = Song(
      id: 'h1',
      sourceId: 's',
      title: '被删',
      artist: '手',
      localPath: missing,
    );
    await provider.songDao.insertSong(song);
    // 造一条已完成任务（无实际文件）
    await provider.downloadTaskDao.upsert(DownloadTask(
      songKey: song.globalKey,
      url: null,
      status: DownloadStatus.completed,
      progress: 1,
      localPath: missing,
    ));
    final dm2 = DownloadManagerImpl(
      songDao: provider.songDao,
      downloadTaskDao: provider.downloadTaskDao,
      customCacheDir: dir.path,
    );
    await dm2.init();
    addTearDown(dm2.dispose);

    expect(await dm2.isCached(song.globalKey), isFalse);
    final stored = await provider.songDao.getSong('h1', 's');
    expect(stored!.localPath, isNull, reason: '自愈应清空 local_path');
    expect(dm2.getTasks().any((t) => t.songKey == song.globalKey), isFalse,
        reason: '自愈应删除任务行');
  });
}
