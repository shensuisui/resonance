/// 壳工程同步装配测试（不 mock 平台）
///
/// 只测纯逻辑：设备 id 生成/复用、资产前缀白名单、状态目录位置。
/// 凭据存储依赖真实 Keystore/Keychain，单测不触碰（真机阶段验证）。
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:resonance_app/sync/sync_wiring.dart';

void main() {
  test('设备 id：首次生成 32 位十六进制并持久化，二次复用', () async {
    final settings = InMemorySettingsDao();
    final wiring = SyncWiring(Directory.systemTemp.path);

    final first = await wiring.ensureDeviceId(settings);
    expect(first.length, 32);
    expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(first), isTrue);

    final second = await wiring.ensureDeviceId(settings);
    expect(second, first);
    expect(await settings.get('sync_device_id'), first);
  });

  test('设备名默认「本机」，可被 settings 覆盖', () async {
    final settings = InMemorySettingsDao();
    final wiring = SyncWiring(Directory.systemTemp.path);
    expect(await wiring.deviceName(settings), '本机');

    await settings.set('sync_device_name', '客厅电脑');
    expect(await wiring.deviceName(settings), '客厅电脑');
  });

  test('状态与资产目录落在注入的私有目录下，且只同步白名单前缀', () {
    final wiring = SyncWiring(p.join('root', 'support'));
    final state = wiring.stateStore();
    expect(state.dir, p.join('root', 'support', 'sync'));

    final assets = wiring.assetStore();
    expect(assets.root, p.join('root', 'support'));
    expect(
      assets.prefixes,
      containsAll(<String>['subscriptions/', 'rules/', 'plugins/']),
    );
  });
}