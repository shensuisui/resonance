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
    this.iconColor,
  }) : isError = false, detail = null, onRetry = null;

  /// 错误态：错误图标 + 错误色 + 「重试」主操作
  ///
  /// [detail] 为异常详情（可选，弱化为副提示）；[onRetry] 提供时显示重试按钮。
  /// 供 album/artist/download/source 等页统一错误展示，避免各页手写裸异常文本。
  const EmptyState.error({
    super.key,
    required this.message,
    this.detail,
    this.onRetry,
  })  : icon = Icons.error_outline_rounded,
        hint = null,
        actionLabel = null,
        onAction = null,
        actionIcon = Icons.refresh_rounded,
        iconColor = null,
        isError = true;

  /// 错误态重试回调（仅 [EmptyState.error] 使用）
  final VoidCallback? onRetry;

  /// 错误态异常详情（仅 [EmptyState.error] 使用）
  final String? detail;

  /// 是否错误态（决定图标/文案用色与重试按钮）
  final bool isError;

  /// 图标层颜色（默认按主题推导）
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 错误态：重试按钮由 onRetry 决定；普通态由 actionLabel + onAction 决定
    final label = isError ? (onRetry == null ? null : '重试') : actionLabel;
    final action = isError ? onRetry : onAction;
    final showAction = label != null && action != null;
    // 错误态副提示展示异常详情；普通态展示 hint
    final subText = isError ? detail : hint;

    // 图标层：浅色圆底 + 主色图标
    // 暗色主题下 primaryContainer 本身偏深，叠半透明会看不见圆底，改用 surfaceContainerHighest
    final circleColor = isError
        ? cs.errorContainer.withValues(alpha: isDark ? 1.0 : 0.5)
        : (isDark
            ? cs.surfaceContainerHighest
            : cs.primaryContainer.withValues(alpha: 0.5));
    final iconTint = iconColor ?? (isError ? cs.error : cs.primary);

    return Center(
      // 横屏可用高度小时避免 Column 溢出：整体可滚动
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.s32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: _circleSize,
              height: _circleSize,
              decoration: BoxDecoration(
                color: circleColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: _iconSize, color: iconTint),
            ),
            const SizedBox(height: AppSpacing.s16),
            Text(
              message,
              style: tt.bodyLarge?.copyWith(
                color: isError ? cs.error : cs.onSurfaceVariant,
                fontWeight: isError ? FontWeight.w600 : null,
              ),
              textAlign: TextAlign.center,
            ),
            if (subText != null && subText.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s8),
              Text(
                subText,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (showAction) ...[
              const SizedBox(height: AppSpacing.s20),
              FilledButton.tonalIcon(
                icon: Icon(isError
                    ? Icons.refresh_rounded
                    : (actionIcon ?? Icons.arrow_forward_rounded)),
                label: Text(label),
                onPressed: action,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 图标层直径（96 = s64 + s32）
  static const double _circleSize = AppSpacing.s64 + AppSpacing.s32;

  /// 图标尺寸
  static const double _iconSize = 44;
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
