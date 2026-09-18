/// 迷你播放器 —— 底部悬浮条
///
/// 显示当前歌曲、播放/暂停按钮、进度条。
/// 点击展开为全屏播放页（S2 后续实现）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radius.dart';
import '../providers/providers.dart';
import '../pages/player_page.dart';
import 'cover_background.dart';
import 'cover_image.dart';
import 'scrollable_text.dart';

class MiniPlayer extends ConsumerWidget {
  /// 点击回调（null 时默认 push 全屏播放页；PlayerOverlay 传入展开回调接管）
  final VoidCallback? onTap;

  const MiniPlayer({super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();

    final isPlaying = ref.watch(isPlayingProvider);
    final position = ref.watch(playbackPositionProvider);
    final duration = ref.watch(playbackDurationProvider);
    final cs = Theme.of(context).colorScheme;

    // 进度 clamp：position 流偶尔会略大于 duration
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 顶部分隔线替代原 elevation 阴影
        Divider(height: 1, color: cs.outlineVariant),
        CoverBackground(
          // 迷你条背景：封面主色(顶部淡色) → 表面色(底部)
          coverUrl: song.coverUrl,
          fallback: cs.surfaceContainerLow,
          topOpacity: 0.45,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap ??
                  () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PlayerPage()),
                    );
                  },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s12,
                  vertical: AppSpacing.s8,
                ),
                child: Row(
                  children: [
                    // 封面
                    _buildCover(song, cs),
                    const SizedBox(width: AppSpacing.s12),
                    // 标题 + 进度
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: ScrollableText(
                                  text: '${song.title} - ${song.artist}',
                                  style:
                                      Theme.of(context).textTheme.bodyMedium,
                                  // 渐变遮罩与迷你条真实底色一致（封面主色混合后的表面色）
                                  fadeColor: cs.surfaceContainerLow,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.s4),
                          LinearProgressIndicator(
                            value: progress,
                            minHeight: 2,
                            backgroundColor: cs.surfaceContainerHighest,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    // 播放/暂停（触觉反馈）
                    IconButton(
                      tooltip: isPlaying ? '暂停' : '播放',
                      icon: Icon(isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        final player = ref.read(playerProvider);
                        if (isPlaying) {
                          player.pause();
                        } else {
                          player.resume();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCover(Song song, ColorScheme cs) {
    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      return CoverImage(
        url: song.coverUrl,
        width: 40,
        height: 40,
        radius: AppRadius.s8,
      );
    }
    return _defaultCover(cs);
  }

  Widget _defaultCover(ColorScheme cs) {
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.s8),
      ),
      child: Icon(Icons.music_note, color: cs.onSurfaceVariant, size: 20),
    );
  }
}

/// Widget 预览：底部迷你播放器（播放中）
///
/// 预览环境无真实服务，用内存 DAO + 假播放器注入；
/// 假播放器仅满足 Player 接口（经 noSuchMethod 转发，预览不触达）。
@Preview(name: 'MiniPlayer 播放中', group: 'MiniPlayer')
Widget miniPlayerPreview() {
  final song = Song(
    id: '1', sourceId: 'netease', title: '晴天', artist: '周杰伦',
  );
  final container = ProviderContainer(overrides: [
    playerProvider.overrideWith((ref) => _PreviewFakePlayer()),
    appDatabaseProvider.overrideWith((ref) => InMemoryDatabaseProvider()),
  ]);
  // 注入播放状态：当前歌曲 + 播放中 + 进度 30s/60s
  container.read(currentSongProvider.notifier).setSong(song);
  container.read(isPlayingProvider.notifier).setPlaying(true);
  container
      .read(playbackPositionProvider.notifier)
      .setPosition(const Duration(seconds: 30));
  container
      .read(playbackDurationProvider.notifier)
      .setDuration(const Duration(seconds: 60));

  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: MiniPlayer())),
  );
}

/// Widget 预览：底部迷你播放器（暂停态，无进度）
@Preview(name: 'MiniPlayer 暂停', group: 'MiniPlayer')
Widget miniPlayerPausedPreview() {
  final song = Song(
    id: '2', sourceId: 'local_scan', title: '稻香', artist: '周杰伦',
  );
  final container = ProviderContainer(overrides: [
    playerProvider.overrideWith((ref) => _PreviewFakePlayer()),
    appDatabaseProvider.overrideWith((ref) => InMemoryDatabaseProvider()),
  ]);
  container.read(currentSongProvider.notifier).setSong(song);
  container.read(isPlayingProvider.notifier).setPlaying(false);

  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: MiniPlayer())),
  );
}

/// 预览用假播放器：只实现 Player 接口中触达的方法，其余 noSuchMethod 转发
class _PreviewFakePlayer implements Player {
  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
