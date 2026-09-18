/// 队列行卡片 Widget —— 播放队列 Sheet 与队列页共用
///
/// 视觉与歌曲卡片（SongTile）一致：surfaceContainerLow 圆角卡片，
/// 当前播放项用 primaryContainer 高亮 + 跳动 EQ 图标。
/// 左侧为序号（当前播放显示 EQ），中部标题/歌手，右侧可选拖拽手柄。
///
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。
library;

import 'package:flutter/material.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radius.dart';

class QueueSongRow extends StatelessWidget {
  /// 队列序号（从 0 开始，展示为 index + 1）
  final int index;

  /// 歌曲标题
  final String title;

  /// 歌手
  final String artist;

  /// 是否当前播放项（高亮 + EQ）
  final bool isCurrent;

  /// 点击回调
  final VoidCallback? onTap;

  /// 右侧尾部组件（如拖拽手柄）
  final Widget? trailing;

  const QueueSongRow({
    super.key,
    required this.index,
    required this.title,
    required this.artist,
    required this.isCurrent,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // 当前播放用 primaryContainer 高亮（对齐 SongTile）
    final containerColor =
        isCurrent ? cs.primaryContainer : cs.surfaceContainerLow;
    final titleColor = isCurrent ? cs.onPrimaryContainer : cs.onSurface;
    final subtitleColor = isCurrent
        ? cs.onPrimaryContainer.withValues(alpha: 0.7)
        : cs.onSurfaceVariant;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(AppRadius.s12),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.s12),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s8,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: isCurrent
                      ? Icon(Icons.graphic_eq_rounded,
                          size: 18, color: cs.onPrimaryContainer)
                      : Text(
                          '${index + 1}',
                          textAlign: TextAlign.center,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyMedium?.copyWith(
                          color: titleColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(color: subtitleColor),
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
