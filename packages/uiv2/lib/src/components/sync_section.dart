/// 设置页「云同步」区块 + 4 个弹层
///
/// 交互（已与用户确认的 9 步）：
///   * 未配置：只有开关（禁用）与「配置」，点开弹出表单；
///   * 配置弹窗：地址/用户名/密码 + 测试连接 + 保存（都是弹出窗口，非行内）；
///   * 已配置且关闭：只留开关与配置（用户拍板）；
///   * 已配置且开启：状态行 + 立即同步 + 历史版本 + 重置；
///   * 历史版本：弹出窗口，列出设备名/时间/触发方式，选中后回滚（二次确认）；
///   * 冲突：状态行提示 + 「详情」弹窗（只读）；
///   * 重置：二次确认（danger）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../providers/sync_providers.dart';
import '../services/sync_service.dart';
import 'sheets.dart';
import 'surfaces.dart';

/// 设置页的云同步区块
class SyncSection extends ConsumerWidget {
  /// 构造
  const SyncSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(syncStatusProvider);
    return async.when(
      loading: () => const UiV2Section(
        title: '云同步',
        child: UiV2Panel(
          padding: EdgeInsets.all(UiV2Spacing.s4),
          child: Text('读取同步状态…'),
        ),
      ),
      error: (e, _) => UiV2Section(
        title: '云同步',
        child: UiV2Panel(
          padding: const EdgeInsets.all(UiV2Spacing.s4),
          child: Text('同步状态读取失败：$e'),
        ),
      ),
      data: (status) => _SyncSectionBody(status: status),
    );
  }
}

class _SyncSectionBody extends ConsumerWidget {
  final SyncStatusView status;

  const _SyncSectionBody({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final notifier = ref.read(syncStatusProvider.notifier);

    // 未配置
    if (!status.configured) {
      return UiV2Section(
        title: '云同步',
        child: UiV2Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              UiV2ListRow(
                label: '启用云同步',
                hint: '未连接 · 数据只在本机',
                leading: _dot(t, t.textMute),
                trailing: const UiV2Switch(
                  value: false,
                  semanticLabel: '启用云同步',
                ),
              ),
              UiV2ListRow(
                label: 'WebDAV 账号',
                hint: '坚果云 / Nextcloud / AList',
                leading: UiV2Icon(UiV2Icons.globe, size: 20, color: t.textDim),
                trailing: UiV2GhostMini(
                  label: '配置',
                  icon: UiV2Icons.edit,
                  onTap: () => _openConfigSheet(context, ref),
                ),
                divider: false,
              ),
            ],
          ),
        ),
      );
    }

    // 已配置但关闭：只留开关与配置
    return UiV2Section(
      title: '云同步',
      child: UiV2Panel(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            UiV2ListRow(
              label: '启用云同步',
              hint: status.enabled ? '已开启' : '已关闭 · 不再自动同步',
              leading: _dot(t, status.enabled ? t.ok : t.textMute),
              trailing: UiV2Switch(
                value: status.enabled,
                semanticLabel: '启用云同步',
                onChanged: (v) async {
                  final r = await notifier.setEnabled(v);
                  if (!context.mounted) return;
                  if (!r.ok) showUiV2Toast(context, r.error ?? '操作失败');
                },
              ),
            ),
            UiV2ListRow(
              label: 'WebDAV 账号',
              hint: status.remoteLabel ?? '已配置',
              leading: UiV2Icon(UiV2Icons.globe, size: 20, color: t.textDim),
              trailing: UiV2GhostMini(
                label: '配置',
                icon: UiV2Icons.edit,
                onTap: () => _openConfigSheet(context, ref),
              ),
              divider: !status.enabled,
            ),
            if (status.enabled) ...[
              UiV2ListRow(
                label: '上次同步',
                hint: _statusHint(status),
                hintColor: _statusColor(t, status),
                leading: _dot(t, _statusColor(t, status) ?? t.textMute),
                trailing: UiV2GhostMini(
                  label: status.phase == SyncPhase.error ? '重试' : '立即同步',
                  icon: UiV2Icons.clock,
                  onTap: () async {
                    final r = await notifier.syncNow();
                    if (!context.mounted) return;
                    showUiV2Toast(context, r.ok ? '同步完成' : (r.error ?? '同步失败'));
                  },
                ),
              ),
              if (status.conflicts.isNotEmpty)
                UiV2ListRow(
                  label: '冲突',
                  hint: '${status.conflicts.length} 条 · 已自动合并',
                  hintColor: t.warn,
                  leading: _dot(t, t.warn),
                  trailing: UiV2GhostMini(
                    label: '详情',
                    icon: UiV2Icons.info,
                    onTap: () => _openConflictSheet(context, status.conflicts),
                  ),
                ),
              UiV2ListRow(
                label: '历史版本',
                hint: '近 7 份 · 可回滚',
                leading: UiV2Icon(UiV2Icons.clock, size: 20, color: t.textDim),
                trailing: UiV2GhostMini(
                  label: '查看',
                  icon: UiV2Icons.chevronRight,
                  onTap: () => _openHistorySheet(context, ref),
                ),
              ),
              UiV2ListRow(
                label: '重置同步',
                hint: '清空云端与本地同步状态',
                leading: UiV2Icon(UiV2Icons.trash, size: 20, color: t.danger),
                trailing: UiV2GhostMini(
                  label: '重置',
                  danger: true,
                  onTap: () => _confirmReset(context, ref),
                ),
                divider: false,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dot(UiV2Tokens t, Color color) => Container(
        width: 9,
        height: 9,
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  Color? _statusColor(UiV2Tokens t, SyncStatusView s) => switch (s.phase) {
        SyncPhase.error => t.danger,
        SyncPhase.conflict => t.warn,
        SyncPhase.idle => t.ok,
        _ => t.textMute,
      };

  String _statusHint(SyncStatusView s) {
    final ver = s.localVersion == null
        ? ''
        : 'v${s.remoteVersion ?? '?'} → v${s.localVersion}';
    final when = s.lastSyncAt == null ? '' : _fmt(s.lastSyncAt!);
    switch (s.phase) {
      case SyncPhase.error:
        return '${s.error ?? '同步失败'} · $when';
      case SyncPhase.conflict:
        return '$ver · 冲突 ${s.conflicts.length}（已自动合并）';
      case SyncPhase.idle:
        return [ver, '成功', when].where((e) => e.isNotEmpty).join(' · ');
      default:
        return '尚未同步';
    }
  }

  String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _openConfigSheet(BuildContext context, WidgetRef ref) async {
    await showUiV2Sheet(
      context,
      title: 'WebDAV 配置',
      child: const _SyncConfigSheet(),
    );
  }

  Future<void> _openHistorySheet(BuildContext context, WidgetRef ref) async {
    await showUiV2Sheet(
      context,
      title: '历史版本',
      child: const _SyncHistorySheet(),
    );
  }

  Future<void> _openConflictSheet(
    BuildContext context,
    List<SyncConflictView> conflicts,
  ) async {
    await showUiV2Sheet(
      context,
      title: '冲突详情',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in conflicts)
            Padding(
              padding: const EdgeInsets.only(bottom: UiV2Spacing.s3),
              child: Text(
                '${_entityLabel(c.entity)}「${c.key}」\n'
                '本机 ${_fmt(c.localAt)} / 远端 ${_fmt(c.remoteAt)}，已自动合并',
                style: UiV2Text.hint,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) {
    return showConfirmSheet(
      context,
      title: '重置同步',
      text: '将清空云端 resonance-sync/ 与本机同步基线，下次同步会重新全量推送本机数据。本机歌单/收藏不会被删除。',
      confirmLabel: '重置',
      onConfirm: () async {
        final r = await ref.read(syncStatusProvider.notifier).reset();
        if (!context.mounted) return;
        showUiV2Toast(context, r.ok ? '已重置同步' : (r.error ?? '重置失败'));
      },
    );
  }

  String _entityLabel(String entity) => switch (entity) {
        'playlists' => '歌单',
        'favorites' => '收藏',
        'settings' => '设置',
        'progress' => '播放进度',
        'songs' => '歌曲',
        'recent' => '最近播放',
        _ => entity,
      };
}

/// WebDAV 配置表单弹层
class _SyncConfigSheet extends ConsumerStatefulWidget {
  const _SyncConfigSheet();

  @override
  ConsumerState<_SyncConfigSheet> createState() => _SyncConfigSheetState();
}

class _SyncConfigSheetState extends ConsumerState<_SyncConfigSheet> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  String? _message;
  bool? _ok;
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _message = null;
      _ok = null;
    });
    final r = await ref.read(syncStatusProvider.notifier).testConnection(
          baseUrl: _url.text,
          username: _user.text,
          password: _pass.text,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = r.ok;
      _message = r.ok ? '连接成功 · 目录可写' : (r.error ?? '连接失败');
    });
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final r = await ref.read(syncStatusProvider.notifier).saveAndEnable(
          baseUrl: _url.text,
          username: _user.text,
          password: _pass.text,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = r.ok;
      _message = r.ok ? null : (r.error ?? '保存失败');
    });
    if (r.ok) {
      Navigator.of(context).maybePop();
      showUiV2Toast(context, '已开启云同步');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_message != null)
          Container(
            margin: const EdgeInsets.only(bottom: UiV2Spacing.s3),
            padding: const EdgeInsets.symmetric(
                horizontal: UiV2Spacing.s3, vertical: UiV2Spacing.s2),
            decoration: BoxDecoration(
              color: (_ok ?? false) ? t.ok.withValues(alpha: 0.12) : t.danger.withValues(alpha: 0.12),
              borderRadius: UiV2Radii.brMd,
            ),
            child: Text(
              _message!,
              style: UiV2Text.hint.copyWith(
                color: (_ok ?? false) ? t.ok : t.danger,
              ),
            ),
          ),
        _field(t, '地址', _url, 'https://dav.jianguoyun.com/dav'),
        _field(t, '用户名', _user, ''),
        _field(t, '密码 / 应用专用密码', _pass, '', obscure: true),
        const SizedBox(height: UiV2Spacing.s2),
        Row(
          children: [
            Expanded(
              child: UiV2Button(
                label: '测试连接',
                variant: UiV2ButtonVariant.soft,
                block: true,
                onTap: _busy ? null : _test,
              ),
            ),
            const SizedBox(width: UiV2Spacing.s3),
            Expanded(
              child: UiV2Button(
                label: '保存',
                variant: UiV2ButtonVariant.primary,
                block: true,
                onTap: _busy ? null : _save,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(
    UiV2Tokens t,
    String label,
    TextEditingController controller,
    String hint, {
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: UiV2Spacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: UiV2Text.hint.copyWith(color: t.textDim)),
          const SizedBox(height: UiV2Spacing.s1),
          TextField(
            controller: controller,
            obscureText: obscure,
            style: UiV2Text.body.copyWith(color: t.text),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: UiV2Text.body.copyWith(color: t.textMute),
              filled: true,
              fillColor: t.surface2,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: UiV2Spacing.s3, vertical: UiV2Spacing.s2),
              border: OutlineInputBorder(
                borderRadius: UiV2Radii.brMd,
                borderSide: BorderSide(color: t.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: UiV2Radii.brMd,
                borderSide: BorderSide(color: t.line),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 历史版本弹层
class _SyncHistorySheet extends ConsumerStatefulWidget {
  const _SyncHistorySheet();

  @override
  ConsumerState<_SyncHistorySheet> createState() => _SyncHistorySheetState();
}

class _SyncHistorySheetState extends ConsumerState<_SyncHistorySheet> {
  late Future<List<SyncVersionView>> _future;
  int? _selected;

  @override
  void initState() {
    super.initState();
    _future = ref.read(syncStatusProvider.notifier).loadVersions();
  }

  String _triggerLabel(String trigger) => switch (trigger) {
        'manual' => '手动同步',
        'auto' => '自动同步',
        _ => '触发未知',
      };

  String _fmt(DateTime? d) {
    if (d == null) return '时间未知';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return FutureBuilder<List<SyncVersionView>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Text('读取版本…');
        }
        final versions = snap.data ?? const <SyncVersionView>[];
        if (versions.isEmpty) return const Text('暂无历史版本');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final v in versions)
              UiV2Pressable(
                onTap: () => setState(() => _selected = v.version),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: UiV2Spacing.s3),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: t.line)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: UiV2Spacing.s2, vertical: 2),
                        decoration: BoxDecoration(
                          color: v.current
                              ? t.accent.withValues(alpha: 0.14)
                              : t.surface2,
                          borderRadius: UiV2Radii.brSm,
                          border: Border.all(
                            color: v.current ? t.accent : t.lineStrong,
                          ),
                        ),
                        child: Text(
                          'v${v.version}',
                          style: UiV2Text.hint.copyWith(
                            color: v.current ? t.accent : t.textDim,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: UiV2Spacing.s3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              v.deviceName,
                              style: UiV2Text.body.copyWith(color: t.text),
                            ),
                            Text(
                              '${_triggerLabel(v.trigger)} · ${_fmt(v.at)}',
                              style: UiV2Text.hint.copyWith(color: t.textMute),
                            ),
                          ],
                        ),
                      ),
                      if (_selected == v.version)
                        UiV2Icon(UiV2Icons.check, size: 18, color: t.accent),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: UiV2Spacing.s4),
            UiV2Button(
              label: '回滚到选中版本',
              variant: UiV2ButtonVariant.danger,
              block: true,
              onTap: _selected == null ? null : () => _confirmRollback(_selected!),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmRollback(int version) {
    return showConfirmSheet(
      context,
      title: '回滚到 v$version',
      text: '将用该版本覆盖本机数据（歌单/收藏/设置/进度）。此操作不可撤销。',
      confirmLabel: '回滚',
      onConfirm: () async {
        final r = await ref.read(syncStatusProvider.notifier).restoreVersion(version);
        if (!context.mounted) return;
        if (r.ok) Navigator.of(context).maybePop();
        showUiV2Toast(context, r.ok ? '已回滚到 v$version' : (r.error ?? '回滚失败'));
      },
    );
  }
}
