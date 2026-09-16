/// 歌单详情头部公共组件
///
/// 供本地歌单（PlaylistDetailPage）与远程歌单（DiscoverPlaylistPage）
/// 复用，保证两端头部视觉一致：
/// - [buildFlexibleSpace]：竖屏 SliverAppBar 折叠头（row[封面, col(名称,描述,操作区)]）
/// - [buildWideColumn]：宽屏左侧信息列（封面 + 名称 + 描述）
///
/// 封面逻辑统一：favorite 用心形主题封面，否则封面图/占位图。
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。
library;

import 'package:flutter/material.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radius.dart';

/// 歌单详情头部公共组件（非 Widget：提供两个构建方法供页面嵌入）
class PlaylistHeader {
  /// 歌单名
  final String name;

  /// 封面 URL（null 或无 cover 来源时显示占位图）
  final String? coverUrl;

  /// 描述文案（如「N 首歌曲」/ 错误信息）
  final String? subtitle;

  /// 是否「我最喜欢」虚拟歌单（心形封面）
  final bool isFavorite;

  /// 「播放全部」回调（null 时按钮禁用态）
  final VoidCallback? onPlayAll;

  const PlaylistHeader({
    required this.name,
    this.coverUrl,
    this.subtitle,
    this.isFavorite = false,
    this.onPlayAll,
  });

  /// 竖屏：SliverAppBar flexibleSpace 内的头部内容
  ///
  /// row[封面(72), col(名称, 描述, 播放全部)]——折叠后仅 AppBar 标题保留。
  Widget buildFlexibleSpace(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      children: [
        _cover(context, cs, size: 72),
        const SizedBox(width: AppSpacing.s16),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: tt.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.s4),
                Text(subtitle!,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: AppSpacing.s8),
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('播放全部'),
                onPressed: onPlayAll,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 宽屏：左侧信息列（封面 + 名称 + 描述）
  Widget buildWideColumn(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cover(context, cs, size: 160),
        const SizedBox(height: AppSpacing.s16),
        Text(name,
            style: tt.headlineSmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.s8),
          Text(subtitle!,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ],
    );
  }

  Widget _cover(BuildContext context, ColorScheme cs, {required double size}) {
    if (isFavorite) {
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.s16),
        ),
        child: Icon(Icons.favorite_rounded,
            color: cs.onPrimaryContainer, size: size * 0.4),
      );
    }
    if (coverUrl != null && coverUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.s16),
        child: Image.network(
          coverUrl!,
          width: size, height: size,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return _defaultCover(cs, size);
          },
          errorBuilder: (_, _, _) => _defaultCover(cs, size),
        ),
      );
    }
    return _defaultCover(cs, size);
  }

  Widget _defaultCover(ColorScheme cs, double size) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.s16),
      ),
      child: Icon(Icons.queue_music_rounded,
          color: cs.onSurfaceVariant, size: size * 0.4),
    );
  }
}