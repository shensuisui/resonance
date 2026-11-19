/// 壳工程侧的云同步装配（不写业务逻辑）
///
/// 只做三件事：
///   1. 凭据进出系统安全存储（Keystore / Keychain / DPAPI）；
///   2. 给出基线目录与资产目录（App 私有目录，前缀白名单）；
///   3. 生成/读取设备 id（存 settings，设备本地、不入云）。
///
/// 设计见 docs/features/webdav-sync.md §9/§11。
library;

import 'dart:math';

import 'package:core/core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sync/sync.dart';

/// WebDAV 凭据
class SyncCredentials {
  /// 服务器地址（如 https://dav.jianguoyun.com/dav）
  final String baseUrl;

  /// 用户名
  final String username;

  /// 密码 / 应用专用密码
  final String password;

  /// 构造
  const SyncCredentials({
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  /// 是否填写完整
  bool get isComplete =>
      baseUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.isNotEmpty;
}

/// 凭据存储：系统安全存储（不写 settings、不入云、不进日志）
class SyncCredentialStore {
  static const String _kBaseUrl = 'sync_base_url';
  static const String _kUsername = 'sync_username';
  static const String _kPassword = 'sync_password';

  final FlutterSecureStorage _storage;

  /// 构造
  const SyncCredentialStore({
    this._storage = const FlutterSecureStorage(),
  });

  /// 读取（缺任一项返回 null）
  Future<SyncCredentials?> read() async {
    final url = await _storage.read(key: _kBaseUrl);
    final user = await _storage.read(key: _kUsername);
    final pass = await _storage.read(key: _kPassword);
    if (url == null || user == null || pass == null) return null;
    final creds = SyncCredentials(baseUrl: url, username: user, password: pass);
    return creds.isComplete ? creds : null;
  }

  /// 写入
  Future<void> write(SyncCredentials creds) async {
    await _storage.write(key: _kBaseUrl, value: creds.baseUrl.trim());
    await _storage.write(key: _kUsername, value: creds.username.trim());
    await _storage.write(key: _kPassword, value: creds.password);
  }

  /// 清空
  Future<void> clear() async {
    await _storage.delete(key: _kBaseUrl);
    await _storage.delete(key: _kUsername);
    await _storage.delete(key: _kPassword);
  }
}

/// 同步路径与设备标识
class SyncWiring {
  /// App 私有根目录（如 applicationSupportDirectory）
  final String supportDir;

  /// 构造
  const SyncWiring(this.supportDir);

  /// 只同步这些子目录（订阅库 / 规则 / 插件）
  static const List<String> assetPrefixes = <String>[
    'subscriptions/',
    'rules/',
    'plugins/',
  ];

  /// 基线/已知版本存储（supportDir/sync）
  FileSyncStateStore stateStore() =>
      FileSyncStateStore(p.join(supportDir, 'sync'));

  /// 资产存储（按前缀白名单，避免把 DB/日志当资产）
  DirectoryAssetStore assetStore() =>
      DirectoryAssetStore(supportDir, prefixes: assetPrefixes);

  /// 设备 id：首次生成后存 settings（设备本地、不入云）
  Future<String> ensureDeviceId(SettingsDao settings) async {
    final existing = await settings.get('sync_device_id');
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _randomId();
    await settings.set('sync_device_id', id);
    return id;
  }

  /// 设备名（默认「本机」，用户可改）
  Future<String> deviceName(SettingsDao settings) async {
    final name = await settings.get('sync_device_name');
    return (name == null || name.isEmpty) ? '本机' : name;
  }

  /// 32 位十六进制随机 id
  String _randomId() {
    final random = Random.secure();
    return List<String>.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }
}

/// 用已保存的凭据构造同步引擎（未配置凭据时抛 [StateError]）
Future<SyncEngine> buildSyncEngine({
  required DatabaseProvider db,
  required SettingsDao settings,
  required String supportDir,
  String remoteRoot = '/resonance-sync',
  SyncCredentialStore credentials = const SyncCredentialStore(),
}) async {
  final creds = await credentials.read();
  if (creds == null || !creds.isComplete) {
    throw StateError('未配置 WebDAV 凭据');
  }
  final wiring = SyncWiring(supportDir);
  return SyncEngine(
    dav: WebdavDavClient(
      baseUrl: creds.baseUrl,
      username: creds.username,
      password: creds.password,
    ),
    db: db,
    state: wiring.stateStore(),
    deviceId: await wiring.ensureDeviceId(settings),
    deviceName: await wiring.deviceName(settings),
    remoteRoot: remoteRoot,
    assetStore: wiring.assetStore(),
  );
}