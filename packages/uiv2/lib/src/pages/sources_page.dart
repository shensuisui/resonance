/// 音乐源（原型 renderSources）：真实源列表来自 SourceManager，可启停与查看详情。
///
/// 「导入插件文件」由壳工程注入的 [PluginHost] 完成（file_picker 这类平台能力
/// 不该被 UI 包直接依赖）；未注入时明确提示，而不是静默失败。
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/rows.dart';
import '../components/source_icon.dart';
import '../components/sheets.dart';
import '../components/surfaces.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../providers/providers.dart';
import '../router.dart';
import '../widgets/page_shell.dart';

/// 音乐源页
class SourcesPage extends ConsumerWidget {
  /// 构造页面
  const SourcesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    // 内置能力（本地音乐/自建歌曲/我最喜欢）声明 visible=false，不进这个列表
    final sources = (ref.watch(sourceListProvider).value ?? const <MusicSource>[])
        .where((s) => s.sourceInfo.visible)
        .toList(growable: false);
    final enabled = ref.watch(enabledSourceMapProvider);
    final enabledCount = enabled.values.where((v) => v).length;

    return PageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(
            title: '音乐源',
            sub: '${sources.length} 个源 · 已启用 $enabledCount 个 · 搜索与推荐只使用已启用的源',
            action: UiV2Button(
              label: '导入插件文件',
              variant: UiV2ButtonVariant.soft,
              onTap: () => _importPlugin(context, ref),
            ),
          ),
          if (sources.isEmpty)
            UiV2Panel(
              child: UiV2Empty(
                title: '还没有音乐源',
                text: '可通过订阅或导入插件文件添加。',
                icon: UiV2Icons.globe,
                actions: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    UiV2Button(
                      label: '导入插件文件',
                      variant: UiV2ButtonVariant.soft,
                      onTap: () => _importPlugin(context, ref),
                    ),
                    const SizedBox(width: UiV2Spacing.s3),
                    UiV2Button(
                      label: '管理订阅',
                      variant: UiV2ButtonVariant.primary,
                      onTap: () => ref.read(navProvider.notifier).go('subs'),
                    ),
                  ],
                ),
              ),
            )
          else
            UiV2Section(
              title: '已注册源（${sources.length}）',
              child: UiV2Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < sources.length; i++)
                      _SourceRow(
                        source: sources[i],
                        enabled: enabled[sources[i].sourceInfo.id] ?? false,
                        divider: i < sources.length - 1,
                      ),
                  ],
                ),
              ),
            ),
          UiV2Section(
            title: '说明',
            child: UiV2Panel(
              padding: const EdgeInsets.all(UiV2Spacing.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '停用某个源后，聚合搜索与推荐都会跳过它；源本身仍保留在列表里，随时可以重新启用。',
                    style: UiV2Text.hint.copyWith(color: t.textDim),
                  ),
                  const SizedBox(height: UiV2Spacing.s3),
                  UiV2Button(
                    label: '管理订阅',
                    variant: UiV2ButtonVariant.soft,
                    onTap: () => ref.read(navProvider.notifier).go('subs'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单条源（.list-row + switch）
class _SourceRow extends ConsumerWidget {
  final MusicSource source;
  final bool enabled;
  final bool divider;

  const _SourceRow({
    required this.source,
    required this.enabled,
    required this.divider,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = source.sourceInfo;
    final typeLabel = switch (info.type) {
      SourceType.local => '本地',
      SourceType.rule => '规则',
      SourceType.plugin => '插件',
    };
    return UiV2ListRow(
      label: info.name,
      hint: 'ID ${info.id} · $typeLabel',
      // 源图标：远程/base64/资源图，缺省用源名首字
      leading: UiV2SourceIconView(source: source, size: 28),
      divider: divider,
      // 点源名打开详情（id / 类型 / 启用状态 / 能力摘要）
      onTap: () => showUiV2Sheet(
        context,
        title: info.name,
        child: _SourceDetailSheet(source: source),
      ),
      trailing: UiV2Switch(
        value: enabled,
        semanticLabel: enabled ? '停用 ${info.name}' : '启用 ${info.name}',
        onChanged: (value) async {
          await ref.read(sourceEnabledActionsProvider).set(info.id, value);
          if (context.mounted) {
            showUiV2Toast(
              context,
              '「${info.name}」${value ? '已启用' : '已停用'}',
            );
          }
        },
      ),
    );
  }
}

/// 选择并导入一个插件文件
///
/// 导入成功后让源列表失效，重新问一次 SourceManager —— 新源这时才出现在列表里。
Future<void> _importPlugin(BuildContext context, WidgetRef ref) async {
  final host = ref.read(pluginHostProvider);
  if (host == null) {
    showUiV2Toast(context, '未接入插件导入：插件文件需要由壳工程提供选择与解析能力');
    return;
  }
  try {
    final name = await host.importPlugin();
    if (!context.mounted) return;
    if (name == null || name.isEmpty) return; // 用户取消，不打扰
    ref.invalidate(sourceListProvider);
    showUiV2Toast(context, '已导入插件源「$name」');
  } catch (error) {
    if (!context.mounted) return;
    showUiV2Toast(context, '导入失败：$error', info: true);
  }
}

/// 源详情弹层：基本信息 + 该源的能力摘要
class _SourceDetailSheet extends ConsumerStatefulWidget {
  /// 目标源
  final MusicSource source;

  /// 构造详情
  const _SourceDetailSheet({required this.source});

  @override
  ConsumerState<_SourceDetailSheet> createState() => _SourceDetailSheetState();
}

class _SourceDetailSheetState extends ConsumerState<_SourceDetailSheet> {
  /// 歌单能力（null = 探测中）：getPlaylistList 返回非空列表即支持
  bool? _supportsPlaylists;

  @override
  void initState() {
    super.initState();
    unawaited(_probe());
  }

  /// 探测歌单能力
  ///
  /// core 的 MusicSource 接口没有能力声明字段，只能问一次：
  /// 拿不到、超时（3 秒）都按「可能不支持」处理并给出人话说明。
  Future<void> _probe() async {
    bool supported;
    try {
      final list = await widget.source
          .getPlaylistList()
          .timeout(const Duration(seconds: 3));
      supported = list.isNotEmpty;
    } catch (_) {
      supported = false;
    }
    if (mounted) setState(() => _supportsPlaylists = supported);
  }

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final info = widget.source.sourceInfo;
    final enabled = ref.watch(enabledSourceMapProvider)[info.id] ?? false;
    final typeLabel = switch (info.type) {
      SourceType.local => '本地',
      SourceType.rule => '规则',
      SourceType.plugin => '插件',
    };
    final playlists = _supportsPlaylists;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiV2ScanStatus(
          lines: [
            ('plain', UiV2Icons.info, 'ID：${info.id}'),
            ('plain', UiV2Icons.library, '类型：$typeLabel'),
            (
              enabled ? 'ok' : 'warn',
              enabled ? UiV2Icons.check : UiV2Icons.close,
              '状态：${enabled ? '已启用' : '已停用'} · 聚合搜索与推荐${enabled ? '会' : '不会'}使用它',
            ),
          ],
        ),
        const SizedBox(height: UiV2Spacing.s4),
        Text('能力摘要', style: UiV2Text.rowLabel.copyWith(color: t.text)),
        const SizedBox(height: UiV2Spacing.s2),
        UiV2ListRow(
          label: '歌单',
          hint: playlists == null
              ? '正在询问来源…'
              : (playlists ? '支持：可以列出并播放该源的歌单' : '未返回歌单列表'),
          trailing: _capabilityBadge(playlists, t),
        ),
        UiV2ListRow(
          label: '歌词',
          hint: '按需向来源请求，空歌词显示空状态',
          divider: false,
          trailing: const UiV2Badge(label: '按需'),
        ),
        const SizedBox(height: UiV2Spacing.s4),
        UiV2Switch(
          value: enabled,
          semanticLabel: enabled ? '停用 ${info.name}' : '启用 ${info.name}',
          onChanged: (value) async {
            await ref.read(sourceEnabledActionsProvider).set(info.id, value);
            if (context.mounted) {
              showUiV2Toast(context, '「${info.name}」${value ? '已启用' : '已停用'}');
            }
          },
        ),
      ],
    );
  }

  /// 歌单能力徽标（探测中显示转圈）
  Widget _capabilityBadge(bool? supported, UiV2Tokens t) {
    if (supported == null) {
      return UiV2Spinner(size: 16, trackColor: t.surface3, color: t.accent);
    }
    return UiV2Badge(
      label: supported ? '支持' : '未知',
      tone: supported ? UiV2BadgeTone.accent : UiV2BadgeTone.plain,
    );
  }
}
