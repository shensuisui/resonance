/// 运行日志（原型 renderLogs）：订阅 core 的 SourceLogBus，保留最近 200 条。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/sheets.dart';
import '../components/surfaces.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../providers/providers.dart';
import '../widgets/page_shell.dart';

/// 运行日志页
class LogsPage extends ConsumerWidget {
  /// 构造页面
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(sourceLogProvider).entries;

    return PageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(
            title: '运行日志',
            sub: '${entries.length} 条记录 · 上限 200 条 · 记录各音乐源的真实执行情况',
          ),
          if (entries.isEmpty)
            const UiV2Panel(
              child: UiV2Empty(
                title: '还没有运行日志',
                text: '搜索、播放等操作会记录各源执行情况。',
                icon: UiV2Icons.note,
              ),
            )
          else ...[
            UiV2Section(
              title: '操作记录（${entries.length}）',
              child: UiV2Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < entries.length; i++)
                      _LogRow(entry: entries[i], divider: i < entries.length - 1),
                  ],
                ),
              ),
            ),
            UiV2Button(
              label: '清空日志',
              variant: UiV2ButtonVariant.soft,
              onTap: () {
                ref.read(sourceLogProvider.notifier).clear();
                showUiV2Toast(context, '运行日志已清空');
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// 单条日志（.list-row + log--warn / log--error）
class _LogRow extends StatelessWidget {
  final SourceLogEntry entry;
  final bool divider;

  const _LogRow({required this.entry, required this.divider});

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final (level, color) = switch (entry.level) {
      SourceLogLevel.error => ('错误', t.danger),
      SourceLogLevel.warn => ('警告', t.warn),
      SourceLogLevel.info => ('信息', t.textDim),
    };
    return UiV2ListRow(
      label: '${entry.action} · ${entry.sourceId}',
      hint: '$level · ${entry.detail}',
      hintColor: color,
      divider: divider,
      trailing: Text(
        entry.timeText,
        style: UiV2Text.hint.copyWith(color: t.textMute),
      ),
    );
  }
}
