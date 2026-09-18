/// 设置页 —— 分级设置（手机二级页 / 宽屏左 tab 右详情）
///
/// 分组：
/// - 外观：主题模式（跟随系统/亮色/暗色）
/// - 本地音乐：扫描目录输入 + 保存/开始扫描
/// - 下载与调试：下载管理、运行日志（二级页）
/// - 订阅：订阅列表 + 右上角添加/全部更新
/// - 源：已注册源列表（含启用开关）+ 右上角导入插件
/// - 关于：版本信息
///
/// 响应式：竖屏显示分组导航，点击进二级详情页；
/// 横屏（宽屏）左侧 NavigationRail 分组 tab，右侧显示分组详情。
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。
library;

import 'package:card_settings_ui/card_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radius.dart';
import '../theme/app_theme.dart';
import '../providers/providers.dart';
import '../widgets/color_picker_dialog.dart';
import 'download_queue_page.dart';
import 'source_log_page.dart';

/// 设置分组
enum SettingsGroup {
  appearance('外观', Icons.palette_outlined),
  localMusic('本地音乐', Icons.music_note_outlined),
  download('下载与调试', Icons.download_for_offline_outlined),
  subscription('订阅', Icons.rss_feed_rounded),
  source('源', Icons.cloud_outlined),
  about('关于', Icons.info_outline_rounded);

  final String label;
  final IconData icon;

  const SettingsGroup(this.label, this.icon);

  static const List<SettingsGroup> all = [
    SettingsGroup.appearance,
    SettingsGroup.localMusic,
    SettingsGroup.download,
    SettingsGroup.subscription,
    SettingsGroup.source,
    SettingsGroup.about,
  ];
}

/// 设置页主入口：竖屏分组导航 → 二级页；横屏左 tab 右详情
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  /// 宽屏模式下当前选中的分组
  SettingsGroup _selected = SettingsGroup.appearance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isWide = orientation == Orientation.landscape;
          if (isWide) {
            // 宽屏：左 tab 右详情（tab 为 icon+名字 一行的基础样式）
            return Row(
              children: [
                SizedBox(
                  width: 200,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.s8),
                    children: [
                      for (final g in SettingsGroup.all)
                        ListTile(
                          selected: _selected == g,
                          selectedTileColor: Theme.of(context)
                              .colorScheme
                              .secondaryContainer
                              .withValues(alpha: 0.5),
                          leading: Icon(g.icon),
                          title: Text(g.label),
                          onTap: () =>
                              setState(() => _selected = g),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: SettingsGroupDetailPage(
                    group: _selected,
                    embedded: true,
                  ),
                ),
              ],
            );
          }
          // 竖屏：分组导航列表 → 二级页
          return ListView(
            children: [
              for (final g in SettingsGroup.all)
                ListTile(
                  leading: Icon(g.icon),
                  title: Text(g.label),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SettingsGroupDetailPage(group: g),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 分组详情页（手机二级页 push；宽屏嵌入为右侧详情）
class SettingsGroupDetailPage extends ConsumerStatefulWidget {
  final SettingsGroup group;

  /// 是否嵌入宽屏（true 时省略 AppBar，由外层编排）
  final bool embedded;

  const SettingsGroupDetailPage({
    super.key,
    required this.group,
    this.embedded = false,
  });

  @override
  ConsumerState<SettingsGroupDetailPage> createState() =>
      _SettingsGroupDetailPageState();
}

class _SettingsGroupDetailPageState
    extends ConsumerState<SettingsGroupDetailPage> {
  final _scanDirController = TextEditingController();
  bool _scanDirLoaded = false;

  @override
  void dispose() {
    _scanDirController.dispose();
    super.dispose();
  }

  Future<void> _loadScanDir() async {
    if (_scanDirLoaded) return;
    final dir = await ref.read(scanProvider.notifier).getScanDir();
    _scanDirController.text = dir ?? '';
    _scanDirLoaded = true;
    if (mounted) setState(() {});
  }

  /// 显示操作结果提示
  void _showMessage(String? message) {
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// 添加订阅对话框（别名 + URL + 手动指定类型）
  Future<(String, SubscriptionType, String)?> _showAddSubscriptionDialog() async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    var type = SubscriptionType.singleRule;
    return showDialog<(String, SubscriptionType, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加订阅'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '别名（可选）',
                  hintText: '如：枫叶音乐、My Music',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              TextField(
                controller: urlController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '订阅地址',
                  hintText: 'https://...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              DropdownButtonFormField<SubscriptionType>(
                initialValue: type,
                decoration: const InputDecoration(
                  labelText: '类型',
                  border: OutlineInputBorder(),
                ),
                items: SubscriptionType.values
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t.label),
                        ))
                    .toList(),
                onChanged: (v) => setDialogState(() => type = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                  context,
                  (urlController.text.trim(), type, nameController.text.trim())),
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  /// 格式化上次检查时间
  String _formatTime(DateTime? time) {
    if (time == null) return '从未检查';
    final m = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$m-$day $hh:$mm';
  }

  /// 添加订阅（右上角操作按钮）
  Future<void> _addSubscription() async {
    final result = await _showAddSubscriptionDialog();
    if (result == null) return;
    final (url, type, name) = result;
    if (url.isEmpty) return;
    await ref
        .read(subscriptionLibraryProvider.notifier)
        .addSubscription(url, type, name: name);
    if (context.mounted) {
      _showMessage(ref.read(subscriptionLibraryProvider).message);
    }
  }

  /// 全部订阅检查更新（右上角操作按钮）
  Future<void> _updateAllSubscriptions() async {
    final (ok, fail) = await ref
        .read(subscriptionLibraryProvider.notifier)
        .updateAll();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新完成：成功 $ok，失败 $fail')),
      );
    }
  }

  /// 导入插件文件（「源」组右上角操作按钮）
  Future<void> _importPlugin() async {
    await ref.read(pluginLibraryProvider.notifier).importFromFile();
    if (context.mounted) {
      _showMessage(ref.read(pluginLibraryProvider).message);
    }
  }

  /// 构建「源」列表 tile：类型图标 + 名称/id + 启用开关
  List<SettingsTile> _buildSourceTiles(
    List<MusicSource> sources,
    Map<String, bool> enabledMap,
    Map<String, String> originMap,
    ColorScheme cs,
    TextTheme tt,
  ) {
    return [
      for (final source in sources)
        SettingsTile.switchTile(
          initialValue: enabledMap[source.sourceInfo.id] ?? false,
          onToggle: (v) {
            ref
                .read(sourceEnabledProvider.notifier)
                .toggle(source.sourceInfo.id, v ?? false);
          },
          leading: Icon(_sourceTypeIcon(source.sourceInfo.type)),
          title: Text(source.sourceInfo.name,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          description: Text(
            _sourceSubtitle(source.sourceInfo, originMap[source.sourceInfo.id]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];
  }

  /// 源类型图标
  IconData _sourceTypeIcon(SourceType type) => switch (type) {
        SourceType.local => Icons.folder_rounded,
        SourceType.rule => Icons.description_rounded,
        SourceType.plugin => Icons.extension_rounded,
      };

  /// 源类型标签
  String _sourceTypeLabel(SourceType type) => switch (type) {
        SourceType.local => '本地',
        SourceType.rule => '规则',
        SourceType.plugin => '插件',
      };

  /// 源副标题：id · 类型[ · 来源]
  String _sourceSubtitle(SourceInfo info, String? origin) {
    final parts = [info.id, _sourceTypeLabel(info.type)];
    if (origin != null && origin.isNotEmpty) {
      final host = Uri.tryParse(origin)?.host;
      parts.add('来自 ${host?.isNotEmpty == true ? host : origin}');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final themeMode = ref.watch(themeModeProvider);
    final scanState = ref.watch(scanProvider);
    final subState = ref.watch(subscriptionLibraryProvider);
    // 源列表（含插件）与启用状态、来源归属
    final sourcesAsync = ref.watch(sourceListProvider);
    final enabledMap = ref.watch(sourceEnabledProvider);
    final originMap = ref.watch(subscriptionLibraryProvider).sourceOrigin;

    final sections = switch (widget.group) {
      SettingsGroup.appearance => [
          SettingsSection(
            title: Text('外观', style: tt.titleSmall?.copyWith(color: cs.primary)),
            tiles: [
              // 子标题：与下方单选卡片分组，避免与分组标题「外观」重复出现同名层级
              _subHeader(cs, tt, '主题模式'),
              SettingsTile.radioTile(
                radioValue: ThemeMode.system,
                groupValue: themeMode,
                onChanged: (v) => ref.read(themeModeProvider.notifier).setMode(v!),
                leading: const Icon(Icons.brightness_auto_rounded),
                title: const Text('跟随系统'),
              ),
              SettingsTile.radioTile(
                radioValue: ThemeMode.light,
                groupValue: themeMode,
                onChanged: (v) => ref.read(themeModeProvider.notifier).setMode(v!),
                leading: const Icon(Icons.light_mode_rounded),
                title: const Text('亮色'),
              ),
              SettingsTile.radioTile(
                radioValue: ThemeMode.dark,
                groupValue: themeMode,
                onChanged: (v) => ref.read(themeModeProvider.notifier).setMode(v!),
                leading: const Icon(Icons.dark_mode_rounded),
                title: const Text('暗色'),
              ),
              _dividerTile(),
              _subHeader(cs, tt, '主题色'),
              // 与 SettingsTile 卡片保持同一容器风格（surfaceContainerLow + 圆角）
              CustomSettingsTile(
                child: (info) => _settingsCard(
                  cs,
                  child: _buildSeedColorPicker(cs, tt),
                ),
              ),
              _subHeader(cs, tt, '全局圆角'),
              CustomSettingsTile(
                child: (info) => _settingsCard(
                  cs,
                  child: _buildCornerRadiusSlider(cs, tt),
                ),
              ),
            ],
          ),
        ],
      SettingsGroup.localMusic => [
          SettingsSection(
            title: Text('本地音乐', style: tt.titleSmall?.copyWith(color: cs.primary)),
            tiles: [
              CustomSettingsTile(
                child: (info) => Padding(
                  padding: const EdgeInsets.all(AppSpacing.s16),
                  child: _buildScanDirPanel(scanState, cs, tt),
                ),
              ),
            ],
          ),
        ],
      SettingsGroup.download => [
          SettingsSection(
            title: Text('下载与调试', style: tt.titleSmall?.copyWith(color: cs.primary)),
            tiles: [
              SettingsTile.navigation(
                leading: const Icon(Icons.download_for_offline_rounded),
                title: const Text('下载管理'),
                description: const Text('查看下载任务，取消或删除缓存'),
                onPressed: (_) => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DownloadQueuePage(),
                  ),
                ),
              ),
              SettingsTile.navigation(
                leading: const Icon(Icons.article_outlined),
                title: const Text('运行日志'),
                description: const Text('查看各音乐源执行情况，排查播放/搜索失败'),
                onPressed: (_) => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SourceLogPage(),
                  ),
                ),
              ),
            ],
          ),
        ],
      SettingsGroup.subscription => [
          SettingsSection(
            title: Row(
              children: [
                Text('订阅', style: tt.titleSmall?.copyWith(color: cs.primary)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  tooltip: '添加订阅',
                  onPressed: _addSubscription,
                ),
                IconButton(
                  icon: const Icon(Icons.sync_rounded),
                  tooltip: '全部检查更新',
                  onPressed: _updateAllSubscriptions,
                ),
              ],
            ),
            tiles: [
              for (final sub in subState.subscriptions)
                SettingsTile.navigation(
                  leading: Icon(sub.type == SubscriptionType.mfGroup ||
                          sub.type == SubscriptionType.singlePlugin
                      ? Icons.extension_rounded
                      : Icons.description_rounded),
                  title: Text(sub.name ?? sub.type.label,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  description: Text(
                    '${sub.type.label} · ${sub.url}\n'
                    '${subState.sourceCounts[sub.url] ?? 0} 源 · 上次检查 ${_formatTime(sub.lastCheckedAt)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: '检查更新',
                        onPressed: () async {
                          await ref
                              .read(subscriptionLibraryProvider.notifier)
                              .updateSubscription(sub.url);
                          _showMessage(
                              ref.read(subscriptionLibraryProvider).message);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        tooltip: '删除订阅',
                        onPressed: () async {
                          await ref
                              .read(subscriptionLibraryProvider.notifier)
                              .removeSubscription(sub.url);
                          _showMessage(
                              ref.read(subscriptionLibraryProvider).message);
                        },
                      ),
                    ],
                  ),
                ),
              if (subState.subscriptions.isEmpty && !subState.loading)
                SettingsTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('暂无订阅，点右上角 + 添加远程规则或插件订阅'),
                ),
            ],
          ),
        ],
      SettingsGroup.source => [
          SettingsSection(
            title: Row(
              children: [
                Text('源', style: tt.titleSmall?.copyWith(color: cs.primary)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.upload_file_rounded),
                  tooltip: '导入插件文件',
                  onPressed: _importPlugin,
                ),
              ],
            ),
            tiles: [
              ..._buildSourceTiles(sourcesAsync.value ?? const [], enabledMap,
                  originMap, cs, tt),
              if ((sourcesAsync.value ?? const []).isEmpty)
                SettingsTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('暂无源，可通过订阅或导入插件添加'),
                ),
            ],
          ),
        ],
      SettingsGroup.about => [
          SettingsSection(
            title: Text('关于', style: tt.titleSmall?.copyWith(color: cs.primary)),
            tiles: [
              SettingsTile(
                leading: const Icon(Icons.music_note_rounded),
                title: const Text('FM 音乐'),
                description: const Text('全源音乐聚合播放器 v1.0.0'),
              ),
            ],
          ),
        ],
    };

    return Scaffold(
      // 嵌入宽屏时不显示 AppBar（由外层编排），push 二级页时显示返回栏
      appBar: widget.embedded ? null : AppBar(title: Text(widget.group.label)),
      body: SettingsList(sections: sections),
    );
  }

  /// 组内分隔线（分隔相邻小节，宽度与卡片一致）
  CustomSettingsTile _dividerTile() {
    return CustomSettingsTile(
      child: (info) => const Padding(
        padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.s12 + AppSpacing.s16, vertical: AppSpacing.s8),
        child: Divider(height: 1),
      ),
    );
  }

  /// 子标题（分组内小节名，左对齐到卡片内容）
  CustomSettingsTile _subHeader(ColorScheme cs, TextTheme tt, String text) {
    return CustomSettingsTile(
      child: (info) => Padding(
        // 左内边距 = 卡片外边距 s12 + 卡内 padding s16，与卡片内容左对齐
        padding: const EdgeInsets.only(
          left: AppSpacing.s12 + AppSpacing.s16,
          right: AppSpacing.s12,
          top: AppSpacing.s12,
          bottom: AppSpacing.s4,
        ),
        child: Text(text, style: tt.labelLarge?.copyWith(color: cs.primary)),
      ),
    );
  }

  /// 设置项卡片容器（与 card_settings_ui 的 SettingsTile 卡片同风格）
  Widget _settingsCard(ColorScheme cs, {required Widget child}) {
    return Container(
      // 卡片间距 s8：大于卡内 padding 的视觉分隔，分组更清晰
      margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12, vertical: AppSpacing.s8),
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.s12),
      ),
      child: child,
    );
  }

  /// 外观：主题色预设色块 + 自定义取色器入口
  Widget _buildSeedColorPicker(ColorScheme cs, TextTheme tt) {
    final current = ref.watch(seedColorProvider);
    final isCustom = !kSeedColorPresets
        .any((p) => p.color.toARGB32() == current.toARGB32());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 色块自适应间距：窄屏（如 444）下缩小间距，避免 6+2 换行时过于松散
        LayoutBuilder(
          builder: (context, cons) {
            const swatch = 44.0;
            const maxSpacing = 16.0;
            const minSpacing = 8.0;
            // 计算一行能放几个（含间距），据此选间距
            final count = kSeedColorPresets.length;
            final total = cons.maxWidth;
            var spacing = maxSpacing;
            while (spacing > minSpacing &&
                count * swatch + (count - 1) * spacing > total) {
              spacing -= 1;
            }
            return Wrap(
              spacing: spacing,
              runSpacing: AppSpacing.s12,
              children: [
                for (final p in kSeedColorPresets)
                  _seedSwatch(
                    cs,
                    color: p.color,
                    selected: p.color.toARGB32() == current.toARGB32(),
                    onTap: () => ref
                        .read(seedColorProvider.notifier)
                        .setSeedColor(p.color),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.s8),
        TextButton.icon(
          onPressed: () async {
            final color =
                await showColorPickerDialog(context, initial: current);
            if (color != null) {
              await ref.read(seedColorProvider.notifier).setSeedColor(color);
            }
          },
          icon: const Icon(Icons.colorize_rounded),
          label: Text(
              isCustom ? '自定义 ${colorToHex(current)}' : '自定义颜色'),
        ),
      ],
    );
  }

  /// 主题色预设色块（圆形，选中打勾）
  Widget _seedSwatch(ColorScheme cs,
      {required Color color,
      required bool selected,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? cs.onSurface : cs.outlineVariant,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, size: 22, color: Colors.white)
            : null,
      ),
    );
  }

  /// 外观：全局圆角滑杆（作用于卡片/对话框/底部弹层）
  Widget _buildCornerRadiusSlider(ColorScheme cs, TextTheme tt) {
    final radius = ref.watch(cornerRadiusProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 滑杆 + 数值整体限宽 380：数值紧贴滑杆右端，避免视线来回跳跃
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Row(
            children: [
              Expanded(
                child: Slider(
                  value: radius.toDouble(),
                  min: kCornerRadiusMin.toDouble(),
                  max: kCornerRadiusMax.toDouble(),
                  divisions: kCornerRadiusMax - kCornerRadiusMin,
                  label: '$radius',
                  onChanged: (v) => ref
                      .read(cornerRadiusProvider.notifier)
                      .setCornerRadius(v.round()),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              SizedBox(
                width: 32,
                child: Text('$radius',
                    textAlign: TextAlign.right,
                    style: tt.bodyMedium?.copyWith(
                        color: cs.onSurface, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        Text('作用于卡片、对话框、底部弹层',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ],
    );
  }

  /// 本地音乐：扫描目录输入 + 保存/开始扫描面板
  Widget _buildScanDirPanel(ScanState scanState, ColorScheme cs, TextTheme tt) {
    _loadScanDir();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _scanDirController,
          decoration: const InputDecoration(
            labelText: '扫描目录',
            hintText: '如 /music 或 C:\\Music',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('保存路径'),
                onPressed: () async {
                  await ref.read(scanProvider.notifier)
                      .setScanDir(_scanDirController.text.trim());
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('扫描目录已保存')),
                  );
                },
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: FilledButton.icon(
                icon: scanState.scanning
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search_rounded),
                label: const Text('开始扫描'),
                onPressed: scanState.scanning
                    ? null
                    : () async {
                        await ref.read(scanProvider.notifier)
                            .setScanDir(_scanDirController.text.trim());
                        await ref.read(scanProvider.notifier).scan();
                      },
              ),
            ),
          ],
        ),
        if (scanState.foundCount != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s8),
            child: Text(
              '扫描完成：新增 ${scanState.foundCount} 首',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        if (scanState.error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s8),
            child: Text(
              '错误：${scanState.error}',
              style: tt.bodySmall?.copyWith(color: cs.error),
            ),
          ),
      ],
    );
  }
}