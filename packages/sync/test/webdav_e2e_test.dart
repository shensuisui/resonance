/// 端到端：真实 WebDAV 服务（shelf_dav 子进程）+ 真实 HTTP + 真实 SQLite
///
/// 覆盖：
///   1. DavClient 原语（写/读/列目录/删除）跑在真实协议上；
///   2. 双设备：首推 v1、增量 v2、删除传播、裁剪到 7 份；
///   3. 历史版本回滚（restoreVersion）。
///
/// 不 mock：服务端是 shelf_dav 真实实现，客户端是 webdav_client_plus，
/// DB 是 sqflite_common_ffi 真实 SQLite 文件。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:db/db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sync/sync.dart';

/// 找到可用的 dart 可执行文件（优先仓库内 SDK）
String _dartExe() {
  final rel = Platform.isWindows
      ? '../../.fvm/flutter_sdk/bin/dart.bat'
      : '../../.fvm/flutter_sdk/bin/dart';
  final f = File(rel);
  if (f.existsSync()) return f.absolute.path;
  return Platform.resolvedExecutable;
}

/// 找一个空闲端口
Future<int> _freePort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}

/// 等服务器就绪（读 READY 行）
Future<void> _waitReady(Process proc, Duration timeout) async {
  final ready = Completer<void>();
  final err = StringBuffer();
  proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (line) {
      if (line.startsWith('READY') && !ready.isCompleted) ready.complete();
    },
  );
  proc.stderr.transform(utf8.decoder).listen(err.write);
  await ready.future.timeout(timeout, onTimeout: () {
    throw StateError('WebDAV 服务未就绪：$err');
  });
}

/// 造一台设备（独立 DB 文件 + 内存状态）
Future<({SyncEngine engine, SqfliteDatabaseProvider db, MemorySyncStateStore state})>
    device(String id, String dbPath, DavClient dav) async {
  final db = SqfliteDatabaseProvider.withHelper(
    DatabaseHelper(customDbPath: dbPath),
  );
  await db.initialize();
  _openedDbs.add(db);
  final state = MemorySyncStateStore();
  return (
    engine: SyncEngine(
      dav: dav,
      db: db,
      state: state,
      deviceId: id,
      deviceName: id,
    ),
    db: db,
    state: state,
  );
}

/// 打开过的 DB：tearDown 先关连接，避免 Windows 上文件被占用删不掉
final _openedDbs = <SqfliteDatabaseProvider>[];

/// 固定时间
DateTime t(int seconds) => DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

void main() {
  late Directory tmp;
  late Process serverProcess;
  late int port;
  late WebdavDavClient dav;


  setUpAll(() async {
    initSqfliteForPlatform();
    tmp = Directory.systemTemp.createTempSync('dav_e2e');
    port = await _freePort();
    serverProcess = await Process.start(
      _dartExe(),
      <String>[
        'run',
        'bin/server.dart',
        '--dir',
        p.join(tmp.path, 'webdav'),
        '--port',
        '$port',
        '--prefix',
        '/dav',
      ],
      workingDirectory: '../sync_dav_server',
    );
    await _waitReady(serverProcess, const Duration(seconds: 45));
    dav = WebdavDavClient(
      baseUrl: 'http://127.0.0.1:$port/dav',
      username: 'test',
      password: 'test',
    );
  });

  tearDownAll(() async {
    serverProcess.kill(ProcessSignal.sigkill);
    await serverProcess.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () => -1,
    );
    for (final db in _openedDbs) {
      await db.close();
    }
    // Windows 上文件句柄释放有延迟：重试几次再删
    for (var i = 0; i < 5 && tmp.existsSync(); i++) {
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  });

  test('DavClient 原语：写/读/列目录/删除', () async {
    await dav.mkdir('/resonance-sync/snapshots');
    await dav.write('/resonance-sync/a.txt', utf8.encode('hello'));
    expect(utf8.decode((await dav.read('/resonance-sync/a.txt'))!), 'hello');
    expect(await dav.read('/resonance-sync/missing.txt'), isNull);

    final entries = await dav.list('/resonance-sync');
    expect(entries.map((e) => e.path.split('/').last), contains('a.txt'));

    await dav.delete('/resonance-sync/a.txt');
    expect(await dav.read('/resonance-sync/a.txt'), isNull);
    // 删除不存在：幂等
    await dav.delete('/resonance-sync/a.txt');
  });

  test('双设备端到端：首推/增量/删除传播/裁剪', () async {
    final a = await device('A', p.join(tmp.path, 'a.db'), dav);
    final b = await device('B', p.join(tmp.path, 'b.db'), dav);

    // 首推 v1
    await a.db.favoritesDao.addFavorite('s:1', 1000);
    final r1 = await a.engine.sync(now: t(10));
    expect(r1.success, isTrue, reason: r1.error);
    expect(r1.pushed, isTrue);
    expect(r1.toVersion, 1);

    // B 拉取并落地（不重复推送）
    final rb = await b.engine.sync(now: t(20));
    expect(rb.success, isTrue, reason: rb.error);
    expect(rb.pushed, isFalse);
    expect(await b.db.favoritesDao.isFavorite('s:1'), isTrue);

    // 增量 v2
    await a.db.favoritesDao.addFavorite('s:2', 2000);
    final r2 = await a.engine.sync(now: t(30));
    expect(r2.pushed, isTrue);
    expect(r2.toVersion, 2);
    await b.engine.sync(now: t(40));
    expect(await b.db.favoritesDao.isFavorite('s:2'), isTrue);

    // 删除传播
    await a.db.favoritesDao.removeFavorite('s:1');
    final r3 = await a.engine.sync(now: t(50));
    expect(r3.pushed, isTrue);
    await b.engine.sync(now: t(60));
    expect(await b.db.favoritesDao.isFavorite('s:1'), isFalse);
    expect(await b.db.favoritesDao.isFavorite('s:2'), isTrue);

    // 裁剪：再多推几次，云端只保留 7 份
    for (var i = 3; i <= 9; i++) {
      await a.db.favoritesDao.addFavorite('s:$i', 1000 + i * 100);
      await a.engine.sync(now: t(60 + i * 10));
    }
    final versions = await a.engine.listVersions();
    expect(versions.length, 7);
  });

  test('历史版本回滚：restoreVersion 恢复旧快照', () async {
    final c = await device('C', p.join(tmp.path, 'c.db'), dav);
    // 云端此时已有 A/B 的数据；先同步拿到最新
    final r0 = await c.engine.sync(now: t(200));
    expect(r0.success, isTrue, reason: r0.error);
    final versions = await c.engine.listVersions();
    expect(versions, isNotEmpty);

    final target = versions.first; // 最旧的一份
    final r = await c.engine.restoreVersion(target, now: t(210));
    expect(r.success, isTrue, reason: r.error);
    expect(r.fromVersion, target);
  });
}