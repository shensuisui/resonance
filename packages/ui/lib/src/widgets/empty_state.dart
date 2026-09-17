/// 空状态 Widget
///
/// 插画式图标层（浅色圆底 + 主色图标）+ 提示文字 + 可选主操作按钮。
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。
library;

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import '../theme/app_spacing.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  /// 副提示（可选，展示在 message 下方）
  final String? hint;

  /// 主操作按钮文案（与 [onAction] 同时提供时显示）
  final String? actionLabel;

  /// 主操作回调
  final VoidCallback? onAction;

  /// 主操作按钮图标（默认箭头）
  final IconData? actionIcon;

  const EmptyState({
    super.key,
    this.icon = Icons.search_off,
    required this.message,
    this.hint,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final showAction = actionLabel != null && onAction != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 插画式图标层：浅色圆底 + 主色图标
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 44, color: cs.primary),
            ),
            const SizedBox(height: AppSpacing.s16),
            Text(
              message,
              style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (hint != null) ...[
              const SizedBox(height: AppSpacing.s8),
              Text(
                hint!,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            if (showAction) ...[
              const SizedBox(height: AppSpacing.s20),
              FilledButton.tonalIcon(
                icon: Icon(actionIcon ?? Icons.arrow_forward_rounded),
                label: Text(actionLabel!),
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Widget 预览：默认空状态（搜索无结果）
@Preview(name: 'EmptyState 默认', group: 'EmptyState')
Widget emptyStatePreview() {
  return const MaterialApp(
    home: Scaffold(body: EmptyState(message: '没有找到相关歌曲')),
  );
}

/// Widget 预览：自定义图标（播放历史为空）
@Preview(name: 'EmptyState 自定义图标', group: 'EmptyState')
Widget emptyStateHistoryPreview() {
  return const MaterialApp(
    home: Scaffold(
      body: EmptyState(
        icon: Icons.history_rounded,
        message: '还没有播放记录',
        hint: '播放过的歌曲会出现在这里',
        actionLabel: '去搜索',
        onAction: _noop,
      ),
    ),
  );
}

void _noop() {}
