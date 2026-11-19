/// ShellSyncService 真实端到端（真实 WebDAV 服务 + 真实 SQLite + 真实目录）
///
/// 覆盖用户可见全链路：保存凭据并开启 → 首推 → 第二台设备拉取 → 增量 →
/// 历史版本明细（设备/触发/时间）→ 回滚 → 重置；以及连不上时的失败返回。
///
/// 服务端用 packages/sync_dav_server（shelf_dav）以子进程运行，客户端是真实
/// webdav_client_plus，不 mock。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:db/db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:resonance_app/sync/shell_sync_service.dart';
import 'package:resonance_app/sync/sync_wiring.dart';
import 'package:uiv2/uiv2.dart';

/// 仓库内 dart
String _dartExe() {
  final rel = Platform.isWindows
      ? '../.fvm/flutter_sdk/bin/dart.bat'
      : '../.fvm/flutter_sdk/bin/dart';
  final f = File(rel);
  return f.existsSync() ? f.absolute.path : Platform.resolvedExecutable;
}

Future<int> _freePort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}

Future<void> _waitReady(Process proc, Duration timeout) async {
  final ready = Completer<void>();
  final err = StringBuffer();
  proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
    if (l.startsWith('READY') && !ready.isCompleted) ready.complete();
  });
  proc.stderr.transform(utf8.decoder).listen(err.write);
  await ready.future.timeout(timeout, onTimeout: () {
    throw StateError('WebDAV 服务未就绪：$err');
  });
}

void main() {
  late Directory tmp;
  late Process server;
  late int port;
  late String baseUrl;

  final services = <ShellSyncService>[];
  final dbs = <SqfliteDatabaseProvider>[];

  Future<ShellSyncService> newService(String name) async {
    final db = SqfliteDatabaseProvider.withHelper(
      DatabaseHelper(customDbPath: p.join(tmp.path, '$name.db')),
    );
    await db.initialize();
    dbs.add(db);
    final support = Directory(p.join(tmp.path, '${name}_support'))..createSync(recursive: true);
    final service = ShellSyncService(
      db: db,
      settings: db.settingsDao,
      credentials: MemoryCredentialStore(),
      supportDirOverride: support.path,
    );
    services.add(service);
    return service;
  }

  setUpAll(() async {
    initSqfliteForPlatform();
    tmp = Directory.systemTemp.createTempSync('shell_sync_e2e');
    port = await _freePort();
    baseUrl = 'http://127.0.0.1:$port/dav';
    server = await Process.start(
      _dartExe(),
      <String>[
        'run', 'bin/server.dart',
        '--dir', p.join(tmp.path, 'webdav'),
        '--port', '$port',
        '--prefix', '/dav',
      ],
      workingDirectory: '../packages/sync_dav_server',
    );
    await _waitReady(server, const Duration(seconds: 60));
  });

  tearDownAll(() async {
    server.kill(ProcessSignal.sigkill);
    await server.exitCode.timeout(const Duration(seconds: 10), onTimeout: () => -1);
    for (final db in dbs) {
      await db.close();
    }
    for (var i = 0; i < 5 && tmp.existsSync(); i++) {
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  });

  test('保存→首推→第二台拉取→增量→历史→回滚→重置', () async {
    final a = await newService('a');
    // 先放一条收藏，再开启同步（应一并推上去）
    final dbA = dbs.last;
    await dbA.favoritesDao.addFavorite('s:1', 1000);

    final enabled = await a.saveAndEnable(
      baseUrl: baseUrl,
      username: 'u',
      password: 'p',
    );
    expect(enabled.ok, isTrue, reason: enabled.error);

    final statusA = await a.loadStatus();
    expect(statusA.configured, isTrue);
    expect(statusA.enabled, isTrue);
    expect(statusA.phase, SyncPhase.idle);
    expect((await a.loadVersions()).isNotEmpty, isTrue);

    // 第二台设备
    final b = await newService('b');
    final dbB = dbs.last;
    final r2 = await b.saveAndEnable(baseUrl: baseUrl, username: 'u', password: 'p');
    expect(r2.ok, isTrue, reason: r2.error);
    expect(await dbB.favoritesDao.isFavorite('s:1'), isTrue);

    // 增量
    await dbA.favoritesDao.addFavorite('s:2', 2000);
    expect((await a.syncNow()).ok, isTrue);
    expect((await b.syncNow()).ok, isTrue);
    expect(await dbB.favoritesDao.isFavorite('s:2'), isTrue);

    // 历史版本：有设备名与触发方式
    final versions = await b.loadVersions();
    expect(versions, isNotEmpty);
    final latest = versions.first;
    expect(latest.current, isTrue);
    expect(latest.deviceName.isNotEmpty, isTrue);
    expect(latest.at, isNotNull);
    expect(latest.trigger, anyOf('manual', 'auto'));

    // 回滚到最旧版本：s:2 应不存在
    final oldest = versions.last.version;
    expect((await b.restoreVersion(oldest)).ok, isTrue);
    expect(await dbB.favoritesDao.isFavorite('s:2'), isFalse);
    expect(await dbB.favoritesDao.isFavorite('s:1'), isTrue);

    // 重置：云端清空
    expect((await b.reset()).ok, isTrue);
    expect(await b.loadVersions(), isEmpty);
  });

  test('连不上时 testConnection 返回失败', () async {
    final s = await newService('c');
    final r = await s.testConnection(
      baseUrl: 'http://127.0.0.1:${await _freePort()}/dav',
      username: 'u',
      password: 'p',
    );
    expect(r.ok, isFalse);
    expect(r.error, isNotNull);
  });
}
