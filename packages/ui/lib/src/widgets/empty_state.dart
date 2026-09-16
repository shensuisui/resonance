/// 空状态 Widget
///
/// 图标 + 提示文字，居中显示。
library;

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import '../theme/app_spacing.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const EmptyState({
    super.key,
    this.icon = Icons.search_off,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: cs.onSurfaceVariant),
            const SizedBox(height: AppSpacing.s16),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
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
    home: Scaffold(body: EmptyState(icon: Icons.history_rounded, message: '还没有播放记录')),
  );
}
