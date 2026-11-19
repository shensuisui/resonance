/// 壳工程侧 SyncService 实现：把 SyncEngine / 安全存储 / 文件基线接到 uiv2 契约
///
/// 职责边界：本文件只做「编排 + 状态缓存 + 视图模型转换」，
/// 合并/网络/DB 细节都在 packages/sync 里。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sync/sync.dart';
import 'package:uiv2/uiv2.dart';

import 'sync_auto_runner.dart';
import 'sync_wiring.dart';

/// 把 baseUrl 变成展示名（坚果云 / Nextcloud / 域名）
String remoteLabelOf(String baseUrl) {
  final trimmed = baseUrl.trim();
  final lower = trimmed.toLowerCase();
  // 关键字可能出现在主机（dav.jianguoyun.com）或路径（/nextcloud）
  if (lower.contains('jianguoyun')) return '坚果云';
  if (lower.contains('nextcloud')) return 'Nextcloud';
  final host = Uri.tryParse(trimmed)?.host ?? '';
  return host.isEmpty ? trimmed : host;
}

/// 状态缓存（设备本地 settings，不入云）
class SyncStatusCache {
  /// 设置键：开关
  static const String kEnabled = 'sync_enabled';

  /// 设置键：上次同步时间
  static const String kLastAt = 'sync_last_at';

  /// 设置键：上次结果（ok/conflict/error）
  static const String kLastStatus = 'sync_last_status';

  /// 设置键：失败原因
  static const String kLastError = 'sync_last_error';

  /// 设置键：本机已知版本
  static const String kLastTo = 'sync_last_to';

  /// 设置键：远端版本
  static const String kLastFrom = 'sync_last_from';

  /// 设置键：冲突明细 JSON
  static const String kLastConflicts = 'sync_last_conflicts';

  /// 设置键：已知设备数
  static const String kDeviceCount = 'sync_device_count';

  final SettingsDao _dao;

  /// 构造
  const SyncStatusCache(this._dao);

  /// 写入一次同步结果
  Future<void> writeReport(SyncReport report) async {
    await _dao.set(kLastAt, DateTime.now().millisecondsSinceEpoch.toString());
    await _dao.set(kLastTo, (report.toVersion ?? 0).toString());
    await _dao.set(kLastFrom, (report.fromVersion ?? 0).toString());
    await _dao.set(kLastStatus, report.success ? (report.conflicts > 0 ? 'conflict' : 'ok') : 'error');
    await _dao.set(kLastError, report.error ?? '');
    await _dao.set(kLastConflicts, jsonEncode(<Object?>[
      for (final c in report.conflictList)
        <String, Object?>{
          'entity': c.entity,
          'key': c.key,
          'localAt': c.localUpdatedAt,
          'remoteAt': c.remoteUpdatedAt,
        },
    ]));
  }

  /// 清空同步结果（重置后）
  Future<void> clearResult() async {
    for (final k in <String>[kLastAt, kLastStatus, kLastError, kLastTo, kLastFrom, kLastConflicts]) {
      await _dao.delete(k);
    }
  }

  /// 读缓存
  Future<({int? lastAt, int? to, int? from, String? status, String? error, List<SyncConflictView> conflicts})>
      read() async {
    final lastAt = await _int(kLastAt);
    final status = await _dao.get(kLastStatus);
    final error = await _dao.get(kLastError);
    final conflicts = <SyncConflictView>[];
    final raw = await _dao.get(kLastConflicts);
    if (raw != null && raw.isNotEmpty) {
      try {
        for (final item in (jsonDecode(raw) as List)) {
          final map = (item as Map).cast<String, Object?>();
          conflicts.add(SyncConflictView(
            entity: map['entity'] as String? ?? '',
            key: map['key'] as String? ?? '',
            localAt: DateTime.fromMillisecondsSinceEpoch((map['localAt'] as num?)?.toInt() ?? 0),
            remoteAt: DateTime.fromMillisecondsSinceEpoch((map['remoteAt'] as num?)?.toInt() ?? 0),
          ));
        }
      } on Object {
        // 缓存损坏：当作没有冲突明细
      }
    }
    return (
      lastAt: lastAt,
      to: await _int(kLastTo),
      from: await _int(kLastFrom),
      status: status,
      error: (error == null || error.isEmpty) ? null : error,
      conflicts: conflicts,
    );
  }

  Future<int?> _int(String key) async {
    final v = await _dao.get(key);
    return v == null ? null : int.tryParse(v);
  }
}

/// [SyncService] 的壳工程实现
class ShellSyncService implements SyncService, AutoSyncHost {
  final DatabaseProvider _db;
  final SettingsDao _settings;
  final SyncCredentialStore _credentials;
  final SyncStatusCache _cache;

  final StreamController<void> _configChanged =
      StreamController<void>.broadcast();

  /// 构造
  ShellSyncService({
    required DatabaseProvider db,
    required SettingsDao settings,
    SyncCredentialStore credentials = const SyncCredentialStore(),
  })  : _db = db,
        _settings = settings,
        _credentials = credentials,
        _cache = SyncStatusCache(settings);

  @override
  Stream<DbChange>? get changes =>
      _db is DbChangeSource ? (_db as DbChangeSource).changes : null;

  @override
  Stream<void> get configChanges => _configChanged.stream;

  @override
  Future<bool> get enabled async =>
      (await _settings.get(SyncStatusCache.kEnabled)) == '1';

  @override
  Future<bool> get wifiOnly async =>
      (await _settings.get('sync_wifi_only') ?? '1') != '0';

  @override
  Future<bool> get startupPull async =>
      (await _settings.get('sync_startup_pull') ?? '1') != '0';

  @override
  Future<int> get debounceMillis async {
    final s = int.tryParse(await _settings.get('sync_debounce_seconds') ?? '') ?? 30;
    return s * 1000;
  }

  @override
  Future<int> get intervalMillis async {
    final m = int.tryParse(await _settings.get('sync_interval_minutes') ?? '') ?? 0;
    return m * 60000;
  }

  /// 自动同步一次（不写 UI 状态之外的东西；供运行器调用）
  @override
  Future<void> syncAuto() async {
    if (!await enabled) return;
    final creds = await _credentials.read();
    if (creds == null || !creds.isComplete) return;
    final engine = await _engine(creds);
    final report = await engine.sync(trigger: 'auto');
    await _cache.writeReport(report);
    try {
      await _settings.set(
        SyncStatusCache.kDeviceCount,
        (await engine.deviceCount()).toString(),
      );
    } on Exception {
      // 设备数只是展示，失败不影响同步
    }
  }

  Future<String> get _supportDir async =>
      (await getApplicationSupportDirectory()).path;

  Future<SyncEngine> _engine(SyncCredentials creds) async {
    final dir = await _supportDir;
    final wiring = SyncWiring(dir);
    return SyncEngine(
      dav: WebdavDavClient(
        baseUrl: creds.baseUrl,
        username: creds.username,
        password: creds.password,
      ),
      db: _db,
      state: wiring.stateStore(),
      deviceId: await wiring.ensureDeviceId(_settings),
      deviceName: await _deviceName(),
      assetStore: wiring.assetStore(),
    );
  }

  Future<String> _deviceName() async {
    final wiring = SyncWiring(await _supportDir);
    final configured = await wiring.deviceName(_settings);
    if (configured != '本机') return configured;
    // 默认用主机名（Android 上是设备名），失败回退「本机」
    final host = Platform.localHostname;
    return host.isEmpty ? '本机' : host;
  }

  @override
  Future<SyncStatusView> loadStatus() async {
    final creds = await _credentials.read();
    final enabled = (await _settings.get(SyncStatusCache.kEnabled)) == '1';
    if (creds == null || !creds.isComplete) {
      return const SyncStatusView.unconfigured();
    }
    final cached = await _cache.read();
    final deviceCount = int.tryParse(await _settings.get(SyncStatusCache.kDeviceCount) ?? '') ?? 0;

    SyncPhase phase;
    if (!enabled) {
      phase = SyncPhase.disabled;
    } else if (cached.status == 'error') {
      phase = SyncPhase.error;
    } else if (cached.status == 'conflict') {
      phase = SyncPhase.conflict;
    } else {
      phase = SyncPhase.idle;
    }
    return SyncStatusView(
      phase: phase,
      remoteLabel: remoteLabelOf(creds.baseUrl),
      localVersion: cached.to,
      remoteVersion: cached.from,
      lastSyncAt: cached.lastAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(cached.lastAt!),
      conflicts: cached.conflicts,
      error: cached.error,
      deviceCount: deviceCount,
      configured: true,
      enabled: enabled,
    );
  }

  @override
  Future<SyncActionResult> testConnection({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final dav = WebdavDavClient(
      baseUrl: baseUrl,
      username: username,
      password: password,
    );
    const root = '/resonance-sync';
    const probe = '/resonance-sync/.probe';
    try {
      await dav.mkdir(root);
      await dav.write(probe, <int>[1]);
      await dav.delete(probe);
      return const SyncActionResult.ok(writable: true);
    } on DavException catch (e) {
      return SyncActionResult.fail(e.message);
    } on Exception catch (e) {
      return SyncActionResult.fail('$e');
    }
  }

  @override
  Future<SyncActionResult> saveAndEnable({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final creds = SyncCredentials(
      baseUrl: baseUrl,
      username: username,
      password: password,
    );
    if (!creds.isComplete) {
      return const SyncActionResult.fail('请填写完整的地址、用户名和密码');
    }
    await _credentials.write(creds);
    await _settings.set(SyncStatusCache.kEnabled, '1');
    _configChanged.add(null);
    return syncNow();
  }

  @override
  Future<SyncActionResult> setEnabled(bool enabled) async {
    await _settings.set(SyncStatusCache.kEnabled, enabled ? '1' : '0');
    _configChanged.add(null);
    if (!enabled) return const SyncActionResult.ok();
    return syncNow();
  }

  @override
  Future<SyncActionResult> syncNow() async {
    final creds = await _credentials.read();
    if (creds == null || !creds.isComplete) {
      return const SyncActionResult.fail('未配置 WebDAV 凭据');
    }
    final engine = await _engine(creds);
    final report = await engine.sync(trigger: 'manual');
    await _cache.writeReport(report);
    if (!report.success) {
      return SyncActionResult.fail(report.error ?? '同步失败');
    }
    // 记录设备数（本地缓存，不发起额外网络）
    final latest = await _safeDeviceCount(engine);
    await _settings.set(SyncStatusCache.kDeviceCount, latest.toString());
    return const SyncActionResult.ok();
  }

  Future<int> _safeDeviceCount(SyncEngine engine) async {
    try {
      return await engine.deviceCount();
    } on Exception {
      return 0;
    }
  }

  @override
  Future<List<SyncVersionView>> loadVersions() async {
    final creds = await _credentials.read();
    if (creds == null || !creds.isComplete) return const <SyncVersionView>[];
    final engine = await _engine(creds);
    final info = await engine.listVersionInfo();
    final current = info.isEmpty ? null : info.last.version;
    return <SyncVersionView>[
      for (final v in info.reversed)
        SyncVersionView(
          version: v.version,
          deviceName: v.writer.isEmpty ? '未知设备' : v.writer,
          at: v.updatedAt == 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch(v.updatedAt),
          trigger: v.trigger,
          current: v.version == current,
        ),
    ];
  }

  @override
  Future<SyncActionResult> restoreVersion(int version) async {
    final creds = await _credentials.read();
    if (creds == null || !creds.isComplete) {
      return const SyncActionResult.fail('未配置 WebDAV 凭据');
    }
    final engine = await _engine(creds);
    final report = await engine.restoreVersion(version);
    if (!report.success) return SyncActionResult.fail(report.error ?? '回滚失败');
    await _cache.clearResult();
    return const SyncActionResult.ok();
  }

  @override
  Future<SyncActionResult> reset() async {
    final creds = await _credentials.read();
    if (creds != null && creds.isComplete) {
      final engine = await _engine(creds);
      await engine.resetRemote();
    }
    await _cache.clearResult();
    await _settings.delete(SyncStatusCache.kDeviceCount);
    _configChanged.add(null);
    return const SyncActionResult.ok();
  }
}
