/// 备份的界面流程：导出全部 / 从文件导入（含预览与模式选择）/ 导出单个歌单
///
/// 与 providers 的分工：这里只做「点按钮 -> 选文件 -> 调服务 -> 出结果」，
/// 具体编解码与合并规则在 core 的 BackupCodec / BackupService 里，可单独测试。
library;

import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/sheets.dart';
import '../components/surfaces.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../providers/providers.dart';
import '../services/file_pickers.dart';

/// 备份文件名的日戳格式（本地时间，便于用户辨认）
String backupFileName(DateTime at) {
  String two(int v) => v < 10 ? '0' + v.toString() : v.toString();
  return 'resonance-backup-v1-' +
      at.year.toString() +
      two(at.month) +
      two(at.day) +
      '-' +
      two(at.hour) +
      two(at.minute) +
      '.json';
}

/// 统计摘要文案（导出/导入后给用户看）
String backupStatsSummary(Map<String, int> stats) {
  final playlists = stats['playlists'] ?? 0;
  final songs = stats['songs'] ?? 0;
  final favorites = stats['favorites'] ?? 0;
  final recent = stats['recent'] ?? 0;
  return playlists.toString() +
      ' 个歌单 / ' +
      songs.toString() +
      ' 首 / ' +
      favorites.toString() +
      ' 收藏 / ' +
      recent.toString() +
      ' 最近播放';
}

/// 导出全部数据（提示保存位置 -> 写文件 -> 记录上次备份）
Future<void> exportAllBackup(BuildContext context, WidgetRef ref) async {
  final service = ref.read(backupServiceProvider);
  final pickers = ref.read(filePickersProvider);
  final doc = await service.exportAll();
  final json = BackupCodec.encode(doc);

  final saved = await pickers.saveTextFile(
    title: '导出全部数据',
    suggestedName: backupFileName(doc.exportedAt),
    extensions: const <String>['json'],
    content: json,
  );
  if (saved == null || saved.isEmpty) return; // 用户取消
  await ref.read(settingsDaoProvider).set(
        'last_backup',
        jsonEncode(<String, dynamic>{
          'at': doc.exportedAt.toUtc().toIso8601String(),
          'stats': doc.stats,
        }),
      );
  ref.invalidate(lastBackupProvider);
  if (context.mounted) {
    showUiV2Toast(context, '已导出：' + backupStatsSummary(doc.stats));
  }
}

/// 导入备份的主流程
///
/// [opened] 非空表示来自系统「用回响打开 .json」（内容已由壳工程读好）。
Future<void> importBackupFlow(
  BuildContext context,
  WidgetRef ref, {
  OpenedFile? opened,
}) async {
  final pickers = ref.read(filePickersProvider);

  String? content = opened?.content;
  String label = opened?.path ?? '';
  if (content == null) {
    final path = await pickers.pickOpenFile(
      title: '选择备份文件',
      extensions: const <String>['json'],
    );
    if (path == null || path.isEmpty) return;
    label = path;
    content = await pickers.readTextFile(path);
  }
  if (content == null) {
    if (context.mounted) showUiV2Toast(context, '读不到文件内容');
    return;
  }

  var legacy = false;
  BackupDocument? document;
  try {
    document = BackupCodec.decode(content);
  } on BackupException catch (error) {
    document = BackupCodec.decodeLegacyPlaylist(content);
    if (document == null) {
      if (context.mounted) showUiV2Toast(context, error.message);
      return;
    }
    legacy = true;
  }

  final doc = document;
  if (!context.mounted) return;

  await showUiV2Sheet(
    context,
    title: '导入备份',
    child: _ImportPreviewBody(
      document: doc,
      sourceLabel: label,
      legacy: legacy,
      onImport: (mode, sections) async {
        final report = await ref
            .read(backupServiceProvider)
            .importDocument(doc, mode: mode, sections: sections);
        if (context.mounted) {
          showUiV2Toast(context, '导入完成：新增 ' + report.totalAdded.toString() +
              ' / 跳过 ' + report.totalSkipped.toString() +
              ' / 更新 ' + report.totalUpdated.toString());
        }
        ref.invalidate(playlistsProvider);
        ref.invalidate(likedProvider);
        ref.invalidate(recentProvider);
      },
    ),
  );
}

/// 导入预览弹层体（可选合并/覆盖 + 分区勾选 + 逐项统计）
class _ImportPreviewBody extends StatefulWidget {
  const _ImportPreviewBody({
    required this.document,
    required this.sourceLabel,
    required this.legacy,
    required this.onImport,
  });

  final BackupDocument document;
  final String sourceLabel;
  final bool legacy;
  final Future<void> Function(BackupImportMode mode, Set<BackupSection> sections)
      onImport;

  @override
  State<_ImportPreviewBody> createState() => _ImportPreviewBodyState();
}

class _ImportPreviewBodyState extends State<_ImportPreviewBody> {
  BackupImportMode _mode = BackupImportMode.merge;
  final Set<BackupSection> _selected = BackupSection.values.toSet();
  bool _busy = false;

  static const Map<BackupSection, String> _labels = <BackupSection, String>{
    BackupSection.playlists: '歌单',
    BackupSection.favorites: '收藏',
    BackupSection.recent: '最近播放',
    BackupSection.settings: '设置',
    BackupSection.progress: '播放进度',
  };

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final stats = widget.document.stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '来自 ' + widget.sourceLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: UiV2Text.hint.copyWith(color: t.textMute),
        ),
        const SizedBox(height: UiV2Spacing.s2),
        Text(
          backupStatsSummary(stats) +
              (widget.legacy ? '（旧版单歌单文件）' : ''),
          style: UiV2Text.bodyDim.copyWith(color: t.textDim),
        ),
        const SizedBox(height: UiV2Spacing.s4),
        Text('导入方式', style: UiV2Text.hint.copyWith(color: t.textMute)),
        const SizedBox(height: UiV2Spacing.s2),
        Wrap(
          spacing: UiV2Spacing.s2,
          children: <Widget>[
            UiV2Chip(
              key: const ValueKey('import_mode_merge'),
              label: '合并（推荐）',
              selected: _mode == BackupImportMode.merge,
              onTap: () => setState(() => _mode = BackupImportMode.merge),
            ),
            UiV2Chip(
              key: const ValueKey('import_mode_overwrite'),
              label: '覆盖（先清空）',
              selected: _mode == BackupImportMode.overwrite,
              onTap: () => setState(() => _mode = BackupImportMode.overwrite),
            ),
          ],
        ),
        const SizedBox(height: UiV2Spacing.s3),
        Text('恢复哪些数据', style: UiV2Text.hint.copyWith(color: t.textMute)),
        const SizedBox(height: UiV2Spacing.s2),
        Wrap(
          spacing: UiV2Spacing.s2,
          runSpacing: UiV2Spacing.s2,
          children: <Widget>[
            for (final section in BackupSection.values)
              UiV2Chip(
                label: _labels[section] ?? section.name,
                selected: _selected.contains(section),
                onTap: () => setState(() {
                  if (_selected.contains(section)) {
                    _selected.remove(section);
                  } else {
                    _selected.add(section);
                  }
                }),
              ),
          ],
        ),
        if (_mode == BackupImportMode.overwrite) ...[
          const SizedBox(height: UiV2Spacing.s3),
          Text(
            '覆盖会先清空勾选分区的现有数据，再写入备份内容；不可撤销。',
            style: UiV2Text.hint.copyWith(color: t.danger),
          ),
        ],
        const SizedBox(height: UiV2Spacing.s5),
        UiV2Button(
          key: const ValueKey('import_confirm'),
          label: _busy ? '导入中…' : '开始导入',
          icon: UiV2Icons.download,
          variant: UiV2ButtonVariant.primary,
          block: true,
          onTap: _busy || _selected.isEmpty
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await widget.onImport(_mode, _selected);
                    if (context.mounted) Navigator.of(context).maybePop();
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
        ),
      ],
    );
  }
}

/// 导出单个歌单：选格式 -> 选保存位置 -> 写文件
Future<void> exportPlaylistFlow(
  BuildContext context,
  WidgetRef ref, {
  required String name,
  required List<Song> songs,
}) async {
  final pickers = ref.read(filePickersProvider);
  // 弹层只负责选格式；结果通过关闭前写入这个变量带回来
  String? chosen;
  await showUiV2Sheet(
    context,
    title: '导出「' + name + '」',
    child: _PlaylistExportBody(
      songCount: songs.length,
      onExport: (format) {
        chosen = format;
        Navigator.of(context, rootNavigator: true).maybePop();
      },
    ),
  );
  if (chosen == null) return;
  final format = chosen!;

  final extension = format == 'json' ? 'json' : (format == 'm3u' ? 'm3u8' : 'csv');
  final content = _encodePlaylist(name, songs, format);
  final saved = await pickers.saveTextFile(
    title: '导出歌单',
    suggestedName: name + '.' + extension,
    extensions: <String>[extension],
    content: content,
  );
  if (saved == null || saved.isEmpty) return;
  if (context.mounted) showUiV2Toast(context, '已导出「' + name + '」');
}

/// 导出面板体：选格式 + 导出按钮
class _PlaylistExportBody extends StatefulWidget {
  const _PlaylistExportBody({required this.songCount, required this.onExport});

  final int songCount;
  final void Function(String format) onExport;

  @override
  State<_PlaylistExportBody> createState() => _PlaylistExportBodyState();
}

class _PlaylistExportBodyState extends State<_PlaylistExportBody> {
  String _format = 'json';

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          widget.songCount.toString() + ' 首 · 回响 JSON 保留来源与元数据快照；' +
              'M3U8/CSV 只带可播地址，给外部播放器用',
          style: UiV2Text.hint.copyWith(color: t.textDim),
        ),
        const SizedBox(height: UiV2Spacing.s4),
        Wrap(
          spacing: UiV2Spacing.s2,
          children: <Widget>[
            UiV2Chip(
              label: '回响 JSON（推荐）',
              selected: _format == 'json',
              onTap: () => setState(() => _format = 'json'),
            ),
            UiV2Chip(
              label: 'M3U8',
              selected: _format == 'm3u',
              onTap: () => setState(() => _format = 'm3u'),
            ),
            UiV2Chip(
              label: 'CSV',
              selected: _format == 'csv',
              onTap: () => setState(() => _format = 'csv'),
            ),
          ],
        ),
        const SizedBox(height: UiV2Spacing.s5),
        UiV2Button(
          label: '导出 ' + widget.songCount.toString() + ' 首',
          icon: UiV2Icons.share,
          variant: UiV2ButtonVariant.primary,
          block: true,
          onTap: () => widget.onExport(_format),
        ),
      ],
    );
  }
}

/// 按所选格式编码（JSON 走无损备份格式；M3U/CSV 只带可播地址）
String _encodePlaylist(String name, List<Song> songs, String format) {
  if (format == 'json') {
    return BackupCodec.encode(BackupDocument(
      exportedAt: DateTime.now(),
      playlists: <BackupPlaylist>[
        BackupPlaylist(
          name: name,
          songs: <BackupSong>[
            for (final song in songs)
              BackupSong(
                songKey: song.globalKey,
                title: song.title,
                artist: song.artist,
                duration: song.duration,
                coverUrl: song.coverUrl,
                localPath: song.localPath,
              ),
          ],
        ),
      ],
    ));
  }
  if (format == 'm3u') {
    final entries = <PlaylistEntry>[
      for (final song in songs)
        PlaylistEntry(
          title: song.title,
          artist: song.artist,
          url: song.playUrl,
          localPath: song.localPath,
        ),
    ];
    return PlaylistCodec.encodeM3U(entries);
  }
  final buffer = StringBuffer('title,artist,source\n');
  for (final song in songs) {
    final source = (song.localPath != null && song.localPath!.isNotEmpty)
        ? song.localPath!
        : (song.playUrl ?? '');
    buffer.writeln(_csv(song.title) + ',' + _csv(song.artist) + ',' + _csv(source));
  }
  return buffer.toString();
}

/// CSV 字段转义（含逗号/引号/换行时整体加引号）
String _csv(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"' + value.replaceAll('"', '""') + '"';
  }
  return value;
}
