/// 歌曲列表项 Widget
///
/// 显示封面、标题、歌手、来源标签，点击播放。
/// 所有颜色用 Theme.colorScheme，间距用 AppSpacing。

import 'package:flutter/material.dart';
import 'package:core/core.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radius.dart';

class SongTile extends StatelessWidget {
  final Song song;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// 歌手名点击回调（传入歌手名），null 则不可点
  final ValueChanged<String>? onArtistTap;

  const SongTile({
    super.key,
    required this.song,
    this.onTap,
    this.trailing,
    this.onArtistTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s4,
      ),
      leading: _buildCover(cs),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge,
      ),
      subtitle: _buildSubtitle(theme.textTheme, cs),
      trailing: trailing,
    );
  }

  /// 副标题：歌手（可点击跳转歌手页）· 来源
  Widget _buildSubtitle(TextTheme theme, ColorScheme cs) {
    final baseStyle = theme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final artistStyle = onArtistTap != null
        ? baseStyle?.copyWith(color: cs.primary)
        : baseStyle;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: GestureDetector(
            onTap: onArtistTap != null ? () => onArtistTap!(song.artist) : null,
            child: Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: artistStyle,
            ),
          ),
        ),
        Text(
          ' · ${song.sourceId}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: baseStyle,
        ),
      ],
    );
  }

  Widget _buildCover(ColorScheme cs) {
    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.s8),
        child: Image.network(
          song.coverUrl!,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultCover(cs),
        ),
      );
    }
    return _defaultCover(cs);
  }

  Widget _defaultCover(ColorScheme cs) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.s8),
      ),
      child: Icon(Icons.music_note, color: cs.onSurfaceVariant, size: 24),
    );
  }
}
