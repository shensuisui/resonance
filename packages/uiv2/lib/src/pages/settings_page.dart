/// 设置页 —— 原型「我的」里的设置项 + v1（ui 包）的设置能力，全部落到真实存储。
///
/// 数据来源：
///   * 主题模式 / 播放模式 / 随机 / 仅 Wi-Fi / 扫描目录 / 音量 → settings 表（与 v1 同键名）
///   * 搜索历史 / 最近播放 → 真实 DAO（可清空）
///   * 扫描按钮 → LocalScanSource.scanFromConfig()
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../uiv2.dart';

/// 设置页
class SettingsPage extends ConsumerWidget {
  /// 构造设置页
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final narrow = MediaQuery.sizeOf(context).width < UiV2Breakpoints.wide;
    final themeMode = ref.watch(themeModeProvider);
    final playMode = ref.watch(playModeProvider);
    final shuffle = ref.watch(shuffleProvider);
    final audioCacheOn = ref.watch(audioCacheEnabledProvider);
    final scanDir = ref.watch(scanDirProvider).value;
    final scan = ref.watch(scanProvider);
    final volume = ref.watch(volumeProvider);
    final history = ref.watch(searchHistoryProvider);
    final recentCount = ref.watch(recentProvider).length;
    final playlistCount = ref.watch(playlistsProvider).value?.length ?? 0;
    final localCount = ref.watch(localTracksProvider).length;

    return PageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHead(title: '设置', sub: '界面、播放、本地扫描与数据清理都在这里。'),

          // ---------- 外观 ----------
          UiV2Section(
            title: '外观',
            child: UiV2Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  // 窄屏放不下「三段控件 + 标签」：会把标签挤成竖排碎字（414px 实测）。
                  // 窄屏把控件换行到标签下方，宽屏才并排。
                  Builder(
                    builder: (context) {
                      final narrow =
                          MediaQuery.sizeOf(context).width < UiV2Breakpoints.wide;
                      final segmented = UiV2Segmented(
                        options: const [
                          ('system', '跟随系统'),
                          ('light', '浅色'),
                          ('dark', '深色'),
                        ],
                        value: switch (themeMode) {
                          ThemeMode.light => 'light',
                          ThemeMode.dark => 'dark',
                          ThemeMode.system => 'system',
                        },
                        // 窄屏换行到整行 → 等分铺满，右边不留空；宽屏并排在行尾
                        expand: narrow,
                        onChanged: (value) => _setThemeMode(ref, value),
                      );
                      // 窄屏：三段控件换行到说明文字下方（作为行内 below，
                      // 自动与文字左对齐，且不再插分隔线）；宽屏并排在右侧。
                      return UiV2ListRow(
                        label: '主题模式',
                        hint: '深色为原型默认，浅色为完整对偶主题',
                        leading: const UiV2FolderIcon(),
                        divider: false,
                        trailing: narrow ? null : segmented,
                        below: narrow ? segmented : null,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // ---------- 播放 ----------
          UiV2Section(
            title: '播放',
            child: UiV2Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  UiV2ListRow(
                    label: '播放模式',
                    hint: '列表循环 / 单曲循环 / 顺序播放',
                    trailing: UiV2GhostMini(
                      label: switch (playMode) {
                        PlayMode.listLoop => '列表循环',
                        PlayMode.singleLoop => '单曲循环',
                        PlayMode.sequential => '顺序播放',
                        PlayMode.shuffle => '随机播放',
                      },
                      icon: UiV2Icons.repeat,
                      onTap: () async {
                        await ref.read(playModeProvider.notifier).cycle();
                        if (context.mounted) {
                          final next = ref.read(playModeProvider);
                          showUiV2Toast(context, switch (next) {
                            PlayMode.listLoop => '列表循环',
                            PlayMode.singleLoop => '单曲循环',
                            PlayMode.sequential => '顺序播放',
                            PlayMode.shuffle => '随机播放',
                          });
                        }
                      },
                    ),
                  ),
                  UiV2ListRow(
                    label: '随机播放',
                    hint: '播放模式的一种：开启后按随机顺序播放，关闭回到上次的循环模式',
                    trailing: UiV2Switch(
                      key: const ValueKey('settings_shuffle_switch'),
                      value: shuffle,
                      semanticLabel: '随机播放',
                      onChanged: (value) async {
                        await ref.read(playModeProvider.notifier).setShuffle(value);
                        if (context.mounted) {
                          showUiV2Toast(
                            context,
                            value ? '随机播放已开启' : '已关闭随机',
                          );
                        }
                      },
                    ),
                  ),
                  UiV2ListRow(
                    label: '音量',
                    hint: '${(volume.volume * 100).round()}%',
                    divider: false,
                    trailing: SizedBox(
                      width: 140,
                      child: UiV2VolumeSliderInline(value: volume.volume, onChanged: (v) => ref.read(volumeProvider.notifier).setVolume(v)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ---------- 本地音乐 ----------
          UiV2Section(
            title: '本地音乐',
            child: UiV2Panel(
              padding: const EdgeInsets.all(UiV2Spacing.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('扫描目录：${scanDir == null || scanDir.isEmpty ? '未设置' : scanDir}', style: UiV2Text.bodyDim.copyWith(color: t.textDim)),
                  const SizedBox(height: UiV2Spacing.s2),
                  Text('已扫描 ${localCount} 首 · 支持 mp3 / flac / aac / wav / m4a / ogg / opus，同名 .lrc 会一起读取。', style: UiV2Text.hint.copyWith(color: t.textDim)),
                  const SizedBox(height: UiV2Spacing.s3),
                  UiV2ScanStatus(
                    lines: [
                      if (scan.scanning) ('plain', UiV2Icons.clock, '正在扫描…'),
                      if (scan.error != null) ('warn', UiV2Icons.info, '扫描失败：${scan.error}'),
                      if (scan.foundCount != null && !scan.scanning)
                        (
                          scan.foundCount! > 0 ? 'ok' : 'warn',
                          UiV2Icons.check,
                          scan.foundCount! > 0 ? '已登记 ${scan.foundCount} 个本地文件。' : '没有新增文件：这些文件重复或无法读取时长。',
                        ),
                      if (!scan.scanning && scan.error == null && scan.foundCount == null) ('plain', UiV2Icons.folder, '点「选择目录」指定要扫描的文件夹。'),
                    ],
                  ),
                  const SizedBox(height: UiV2Spacing.s3),
                  Row(
                    children: [
                      Expanded(
                        child: UiV2Button(
                          label: scanDir == null || scanDir.isEmpty ? '选择目录' : '换个目录',
                          icon: UiV2Icons.folder,
                          variant: UiV2ButtonVariant.soft,
                          onTap: () => _pickDirectory(context, ref, scanDir),
                        ),
                      ),
                      const SizedBox(width: UiV2Spacing.s2),
                      Expanded(
                        child: UiV2Button(
                          label: scan.scanning ? '扫描中…' : '开始扫描',
                          icon: UiV2Icons.download,
                          variant: UiV2ButtonVariant.primary,
                          onTap: scan.scanning
                              ? null
                              : () async {
                                  if (scanDir == null || scanDir.isEmpty) {
                                    showUiV2Toast(context, '请先选择扫描目录');
                                    return;
                                  }
                                  await ref.read(scanProvider.notifier).scan();
                                  if (context.mounted) {
                                    final s = ref.read(scanProvider);
                                    showUiV2Toast(context, s.error != null ? '扫描失败：${s.error}' : '已登记 ${s.foundCount ?? 0} 个本地文件');
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ---------- 下载设置 ----------
          UiV2Section(
            title: '下载设置',
            child: UiV2Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _downloadSegRow(
                    context,
                    narrow: narrow,
                    label: '文件命名',
                    hint: '下载文件名顺序，默认「歌手 - 歌曲」',
                    options: const [
                      ('artist_title', '歌手 - 歌曲'),
                      ('title_artist', '歌曲 - 歌手'),
                    ],
                    value: ref.watch(downloadNameOrderProvider),
                    onChanged: (v) =>
                        ref.read(downloadNameOrderProvider.notifier).set(v),
                  ),
                  _downloadSegRow(
                    context,
                    narrow: narrow,
                    label: '封面缩略图',
                    hint: '嵌入封面的尺寸（缩略图）',
                    options: const [
                      ('256', '256'),
                      ('512', '512'),
                      ('1024', '1024'),
                    ],
                    value: '${ref.watch(downloadCoverSizeProvider)}',
                    onChanged: (v) => ref
                        .read(downloadCoverSizeProvider.notifier)
                        .set(int.parse(v)),
                  ),
                  _downloadSegRow(
                    context,
                    narrow: narrow,
                    label: '封面质量',
                    hint: '缩略图 JPEG 质量',
                    options: const [('85', '85'), ('90', '90')],
                    value: '${ref.watch(downloadCoverQualityProvider)}',
                    onChanged: (v) => ref
                        .read(downloadCoverQualityProvider.notifier)
                        .set(int.parse(v)),
                    divider: false,
                  ),
                  UiV2ListRow(
                    label: '下载目录',
                    hint: ref.watch(downloadDirProvider).value ??
                        '应用支持目录 / downloads',
                    leading: UiV2Icon(UiV2Icons.folder, size: 20, color: t.textDim),
                    divider: false,
                  ),
                ],
              ),
            ),
          ),

          // ---------- 数据备份 ----------
          UiV2Section(
            title: '数据备份',
            child: UiV2Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  UiV2ListRow(
                    key: const ValueKey('settings_backup_export'),
                    label: '导出全部数据',
                    hint: '歌单 / 收藏 / 最近播放 / 设置 / 播放进度 · 一个 .json 文件',
                    leading: UiV2Icon(UiV2Icons.share, size: 20, color: t.textDim),
                    trailing: UiV2GhostMini(
                      key: const ValueKey('settings_backup_export_btn'),
                      label: '导出',
                      icon: UiV2Icons.share,
                      onTap: () => exportAllBackup(context, ref),
                    ),
                  ),
                  UiV2ListRow(
                    key: const ValueKey('settings_backup_import'),
                    label: '从文件导入',
                    hint: 'Android 也可在文件管理器里「用回响打开」备份 .json',
                    leading: UiV2Icon(UiV2Icons.download, size: 20, color: t.textDim),
                    trailing: UiV2GhostMini(
                      key: const ValueKey('settings_backup_import_btn'),
                      label: '选择',
                      icon: UiV2Icons.folder,
                      onTap: () => importBackupFlow(context, ref),
                    ),
                  ),
                  UiV2ListRow(
                    key: const ValueKey('settings_backup_last'),
                    label: '最近一次备份',
                    hint: _lastBackupHint(ref.watch(lastBackupProvider)),
                    leading: UiV2Icon(UiV2Icons.clock, size: 20, color: t.textDim),
                    divider: false,
                  ),
                ],
              ),
            ),
          ),

          // ---------- 数据 ----------
          UiV2Section(
            title: '数据',
            child: UiV2Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  UiV2ListRow(
                    label: '我喜欢的音乐',
                    hint: '${ref.watch(favoriteCountProvider)} 首（真实收藏表）',
                    trailing: UiV2GhostMini(label: '查看', onTap: () => Navigator.of(context).maybePop()),
                  ),
                  UiV2ListRow(label: '歌单', hint: '$playlistCount 个（真实歌单表）', divider: false),
                  UiV2ListRow(
                    label: '最近播放',
                    hint: '$recentCount 首',
                    trailing: UiV2GhostMini(
                      label: '清空',
                      danger: true,
                      onTap: () => showConfirmSheet(
                        context,
                        title: '清空最近播放',
                        text: '将删除全部最近播放记录，不影响收藏与歌单。',
                        confirmLabel: '清空',
                        onConfirm: () async {
                          await ref.read(recentProvider.notifier).clear();
                          if (context.mounted) showUiV2Toast(context, '已清空最近播放');
                        },
                      ),
                    ),
                  ),
                  UiV2ListRow(
                    label: '搜索历史',
                    hint: '${history.length} 条',
                    divider: true,
                    trailing: UiV2GhostMini(
                      label: '清空',
                      danger: true,
                      onTap: () async {
                        await ref.read(searchHistoryProvider.notifier).clear();
                        if (context.mounted) showUiV2Toast(context, '已清空搜索历史');
                      },
                    ),
                  ),
                  UiV2ListRow(
                    key: const ValueKey('settings_audio_cache'),
                    label: '播放时自动缓存',
                    hint: '听过的歌下次播放不再请求远程，源失效也能播（与「已下载」分开存放）',
                    divider: true,
                    trailing: UiV2Switch(
                      value: audioCacheOn,
                      semanticLabel: '播放时自动缓存',
                      onChanged: (value) async {
                        await ref.read(audioCacheEnabledProvider.notifier).set(value);
                        if (context.mounted) {
                          showUiV2Toast(
                              context, value ? '播放时自动缓存：已开启' : '播放时自动缓存：已关闭');
                        }
                      },
                    ),
                  ),
                  UiV2ListRow(
                    key: const ValueKey('settings_audio_cache_clear'),
                    label: '播放缓存',
                    hint: _audioCacheHint(ref.watch(audioCacheSizeProvider)),
                    divider: true,
                    trailing: UiV2GhostMini(
                      label: '清空',
                      danger: true,
                      onTap: () async {
                        await ref.read(audioCacheProvider).clear();
                        if (context.mounted) showUiV2Toast(context, '已清空播放缓存');
                      },
                    ),
                  ),
                  UiV2ListRow(
                    key: const ValueKey('settings_image_cache'),
                    label: '图片缓存',
                    hint: '封面等网络图：磁盘缓存 '
                        '${kUiV2ImageCachePolicy.maxAgeDays} 天 / 最多 '
                        '${kUiV2ImageCachePolicy.maxObjects} 个',
                    divider: false,
                    trailing: UiV2GhostMini(
                      label: '清理',
                      danger: true,
                      onTap: () async {
                        await clearUiV2ImageCache();
                        if (context.mounted) showUiV2Toast(context, '已清理图片缓存');
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ---------- 关于 ----------
          UiV2Section(
            title: '关于',
            child: UiV2Panel(
              padding: EdgeInsets.zero,
              child: UiV2ListRow(
                label: '回响 Resonance · uiv2',
                hint: '按 OpenDesign 原型实现的第二套界面，数据全部走项目既有能力',
                divider: false,
                trailing: UiV2GhostMini(
                  label: '说明',
                  onTap: () => showUiV2Sheet(context, title: '关于这个界面', child: const _AboutBody()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 输入扫描目录（桌面端手输路径；不依赖 file_picker，避免给 uiv2 增加平台依赖）
  Future<void> _pickDirectory(BuildContext context, WidgetRef ref, String? current) async {
    final controller = TextEditingController(text: current ?? '');
    await showUiV2Sheet(
      context,
      title: '扫描目录',
      child: Builder(
        builder: (context) {
          final t = UiV2Theme.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('填写本机绝对路径，例如 D:\\Music。扫描只读取文件名、时长与同名 .lrc。', style: UiV2Text.hint.copyWith(color: t.textDim)),
              const SizedBox(height: UiV2Spacing.s3),
              TextField(
                controller: controller,
                autofocus: true,
                style: UiV2Text.body.copyWith(color: t.text),
                decoration: InputDecoration(
                  hintText: 'D:\\Music',
                  hintStyle: UiV2Text.body.copyWith(color: t.textMute),
                  filled: true,
                  fillColor: t.surface2,
                  contentPadding: const EdgeInsets.symmetric(horizontal: UiV2Spacing.s4, vertical: UiV2Spacing.s3),
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
              const SizedBox(height: UiV2Spacing.s4),
              UiV2Button(
                label: '保存并扫描',
                icon: UiV2Icons.check,
                variant: UiV2ButtonVariant.primary,
                block: true,
                onTap: () async {
                  final path = controller.text.trim();
                  if (path.isEmpty) {
                    showUiV2Toast(context, '请输入目录路径');
                    return;
                  }
                  Navigator.of(context).maybePop();
                  await ref.read(scanProvider.notifier).scanDirectory(path);
                  if (context.mounted) {
                    final s = ref.read(scanProvider);
                    showUiV2Toast(context, s.error != null ? '扫描失败：${s.error}' : '已登记 ${s.foundCount ?? 0} 个本地文件');
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 设置页内的音量滑块（复用播放条的量条样式）
class UiV2VolumeSliderInline extends StatelessWidget {
  /// 当前音量 0~1
  final double value;

  /// 变化回调
  final ValueChanged<double> onChanged;

  /// 构造滑块
  const UiV2VolumeSliderInline({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: t.accent,
        inactiveTrackColor: t.surface3,
        thumbColor: t.text,
        overlayColor: t.accentSoft,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      child: Slider(value: value.clamp(0, 1), onChanged: onChanged),
    );
  }
}

/// 关于说明
class _AboutBody extends StatelessWidget {
  const _AboutBody();

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    const paragraphs = [
      '界面按 OpenDesign 原型「回响 Resonance」实现：深色优先的令牌系统、侧栏/底栏自适应、沉浸播放页与歌词舞台。',
      '数据全部来自项目既有能力：收藏、歌单、最近播放、设置走 SQLite（DAO），搜索走 SourceManager 聚合已启用源，歌曲与歌词由各源提供。',
      '演示曲库是一个本地 HTTP 调试源，只在 Debug 构建中可用；Release 不注册、也不打包其数据与资源。',
      '本地音乐来自扫描结果，扫描目录在「设置 → 本地音乐」里指定。',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final text in paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: UiV2Spacing.s3),
            child: Text(text, style: UiV2Text.bodyDim.copyWith(color: t.textDim)),
          ),
        const SizedBox(height: UiV2Spacing.s3),
        UiV2Button(label: '知道了', variant: UiV2ButtonVariant.primary, block: true, onTap: () => Navigator.of(context).maybePop()),
      ],
    );
  }
}


/// 播放缓存占用文案（设置页展示用）
///
/// 未就绪时显示"统计中…"；0 字节显示"暂无缓存"，避免"占用 0 MB"这种误导。
String _audioCacheHint(AsyncValue<int> size) {
  final bytes = size.value;
  if (bytes == null) return '统计中…';
  if (bytes <= 0) return '暂无缓存';
  if (bytes < 1024 * 1024) return '占用 ${(bytes / 1024).toStringAsFixed(0)} KB';
  return '占用 ${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// 设置主题模式（窄屏与宽屏两套布局共用同一份逻辑）
void _setThemeMode(WidgetRef ref, String value) {
  ref.read(themeModeProvider.notifier).setMode(switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  });
}

/// 最近一次备份的展示文案（没有备份/损坏时给明确说明，不显示假时间）
String _lastBackupHint(AsyncValue<LastBackupInfo?> info) {
  final value = info.value;
  if (info.isLoading && value == null) return '读取中…';
  if (value == null) return '还没有备份过';
  String two(int v) => v < 10 ? '0' + v.toString() : v.toString();
  final at = value.at.toLocal();
  final stamp = at.year.toString() + '-' + two(at.month) + '-' + two(at.day) +
      ' ' + two(at.hour) + ':' + two(at.minute);
  return stamp + ' · ' + backupStatsSummary(value.stats);
}


/// 下载设置的一段：宽屏行尾放分段控件，窄屏上下堆叠（复用真实组件）
Widget _downloadSegRow(
  BuildContext context, {
  required bool narrow,
  required String label,
  required String hint,
  required List<(String, String)> options,
  required String value,
  required ValueChanged<String> onChanged,
  bool divider = true,
}) {
  final control = UiV2Segmented(
    options: options,
    value: value,
    onChanged: onChanged,
    expand: narrow,
  );
  if (!narrow) {
    return UiV2ListRow(
      label: label,
      hint: hint,
      divider: divider,
      trailing: control,
    );
  }
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: UiV2Text.trackTitle),
        Text(hint, style: UiV2Text.hint),
        const SizedBox(height: 8),
        control,
      ],
    ),
  );
}
