/// SyncSection widget 测试
///
/// 用假 SyncService 驱动四种状态，验证区块按确认过的交互渲染：
///   未配置 / 已配置关闭（只留开关+配置）/ 已配置开启（状态+三入口）/ 冲突。
///
/// 真实引擎与协议由 packages/sync 的 e2e 覆盖，这里只验证 UI 契约。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/uiv2.dart';

/// 可配置的假服务
class FakeSyncService implements SyncService {
  SyncStatusView status;
  int syncCalls = 0;
  int resetCalls = 0;

  FakeSyncService(this.status);

  @override
  Future<SyncStatusView> loadStatus() async => status;

  @override
  Future<SyncActionResult> testConnection({
    required String baseUrl,
    required String username,
    required String password,
  }) async =>
      const SyncActionResult.ok(writable: true);

  @override
  Future<SyncActionResult> saveAndEnable({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    status = SyncStatusView(
      phase: SyncPhase.idle,
      remoteLabel: '坚果云',
      configured: true,
      enabled: true,
    );
    return const SyncActionResult.ok();
  }

  @override
  Future<SyncActionResult> setEnabled(bool enabled) async {
    status = SyncStatusView(
      phase: enabled ? SyncPhase.idle : SyncPhase.disabled,
      remoteLabel: status.remoteLabel,
      configured: true,
      enabled: enabled,
    );
    return const SyncActionResult.ok();
  }

  @override
  Future<SyncActionResult> syncNow() async {
    syncCalls++;
    return const SyncActionResult.ok();
  }

  @override
  Future<List<SyncVersionView>> loadVersions() async => const <SyncVersionView>[
        SyncVersionView(version: 3, deviceName: '客厅电脑', trigger: 'manual', current: true),
        SyncVersionView(version: 2, deviceName: 'Pixel 7', trigger: 'auto'),
      ];

  @override
  Future<SyncActionResult> restoreVersion(int version) async =>
      const SyncActionResult.ok();

  @override
  Future<SyncActionResult> reset() async {
    resetCalls++;
    return const SyncActionResult.ok();
  }
}

/// 渲染区块
Future<FakeSyncService> pumpSection(
  WidgetTester tester,
  SyncStatusView status,
) async {
  final fake = FakeSyncService(status);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [syncServiceProvider.overrideWithValue(fake)],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: SyncSection())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('未配置：只有开关与「配置」，无同步按钮', (tester) async {
    await pumpSection(tester, const SyncStatusView.unconfigured());
    expect(find.text('云同步'), findsOneWidget);
    expect(find.text('配置'), findsOneWidget);
    expect(find.text('立即同步'), findsNothing);
    expect(find.text('历史版本'), findsNothing);
  });

  testWidgets('已配置关闭：只留开关与配置', (tester) async {
    await pumpSection(
      tester,
      const SyncStatusView(
        phase: SyncPhase.disabled,
        remoteLabel: '坚果云',
        configured: true,
        enabled: false,
      ),
    );
    expect(find.text('配置'), findsOneWidget);
    expect(find.text('立即同步'), findsNothing);
    expect(find.text('历史版本'), findsNothing);
    expect(find.text('重置同步'), findsNothing);
  });

  testWidgets('已配置开启：状态行 + 立即同步/历史版本/重置，点立即同步会调用', (tester) async {
    final fake = await pumpSection(
      tester,
      SyncStatusView(
        phase: SyncPhase.idle,
        remoteLabel: '坚果云',
        localVersion: 42,
        remoteVersion: 41,
        lastSyncAt: DateTime(2026, 11, 19, 22, 41),
        configured: true,
        enabled: true,
      ),
    );
    expect(find.text('上次同步'), findsOneWidget);
    expect(find.text('历史版本'), findsOneWidget);
    expect(find.text('重置同步'), findsOneWidget);
    expect(find.text('立即同步'), findsOneWidget);

    await tester.tap(find.text('立即同步'));
    await tester.pumpAndSettle();
    // toast 自带计时器：让它走完，否则测试结束会报 pending timer
    await tester.pump(const Duration(seconds: 5));
    expect(fake.syncCalls, 1);
  });

  testWidgets('冲突：状态行显示冲突条数与详情入口', (tester) async {
    await pumpSection(
      tester,
      SyncStatusView(
        phase: SyncPhase.conflict,
        remoteLabel: 'Nextcloud',
        localVersion: 43,
        remoteVersion: 42,
        configured: true,
        enabled: true,
        conflicts: <SyncConflictView>[
          SyncConflictView(
            entity: 'playlists',
            key: '夜行',
            localAt: DateTime(2026, 11, 19, 20),
            remoteAt: DateTime(2026, 11, 19, 21),
          ),
        ],
      ),
    );
    expect(find.text('冲突'), findsOneWidget);
    expect(find.textContaining('已自动合并'), findsWidgets);
    expect(find.text('详情'), findsOneWidget);
  });

  testWidgets('点「配置」弹出表单：有地址/用户名/密码与测试连接、保存', (tester) async {
    await pumpSection(tester, const SyncStatusView.unconfigured());
    await tester.tap(find.text('配置'));
    await tester.pumpAndSettle();

    expect(find.text('WebDAV 配置'), findsOneWidget);
    expect(find.text('地址'), findsOneWidget);
    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('密码 / 应用专用密码'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
  });
}
