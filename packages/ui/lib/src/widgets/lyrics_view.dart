/// 同步歌词视图
///
/// 根据播放进度高亮当前歌词行并自动滚动居中。
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。
library;

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../providers/providers.dart';
import '../theme/app_spacing.dart';
import 'cover_image.dart';
import 'empty_state.dart';

class LyricsView extends ConsumerStatefulWidget {
  const LyricsView({super.key});

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  final _scrollController = ScrollController();

  /// 每行固定高度（两行文本 + 行距，保证长句换行后仍可居中）
  static const double _lineHeight = AppSpacing.s48 + AppSpacing.s12;

  /// 上一次已滚动到的歌词行（避免重复滚动打断用户操作）
  int _lastScrolledIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 找到当前播放位置对应的歌词行索引（最后一个 time <= position 的行）
  int _currentIndex(List<LyricLine> lines, Duration position) {
    var index = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].time <= position) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lyrics = ref.watch(lyricsProvider);
    final position = ref.watch(playbackPositionProvider);
    // 当前歌曲封面（歌词背景模糊源）
    final song = ref.watch(currentSongProvider);
    final coverUrl = song?.coverUrl;

    if (lyrics == null) {
      // 空态统一走 EmptyState（图标 + 文案 + 提示）
      return const EmptyState(
        icon: Icons.lyrics_outlined,
        message: '暂无歌词',
        hint: '该音乐源未提供歌词',
      );
    }

    final currentIndex = _currentIndex(lyrics.lines, position);

    // 高亮行滚动到可视区中部：target 需减去半个视口，使当前行落在中央
    // （仅在行号变化时触发，避免进度流每次推送都打断用户手动滚动）
    if (currentIndex != _lastScrolledIndex) {
      _lastScrolledIndex = currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        if (currentIndex < 0) return;
        final vp = _scrollController.position.viewportDimension;
        // 行高按两行文本预留：长句换行时不会被下一行压住
        final target =
            currentIndex * _lineHeight - (vp - _lineHeight) / 2;
        final offset = _scrollController.offset;
        if ((target - offset).abs() > 2) {
          _scrollController.animateTo(
            target.clamp(0.0, _scrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // 封面模糊背景（沉浸增强）
        if (coverUrl != null && coverUrl.isNotEmpty)
          Positioned.fill(
            // 封面模糊背景：走 CoverImage（带缓存），小尺寸解码后模糊，避免整图掉帧
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: CoverImage(
                url: coverUrl,
                fit: BoxFit.cover,
                radius: 0,
              ),
            ),
          ),
        // 表面色半透明罩：让主题色透出，保证文字对比度
        Positioned.fill(
          child: Container(color: cs.surface.withValues(alpha: 0.6)),
        ),
        // 歌词列表（LayoutBuilder 提供视口高度，用于首末行居中的动态留白）
        LayoutBuilder(
          builder: (context, cons) {
            final pad = (cons.maxHeight - _lineHeight) / 2;
            return ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.symmetric(
                  vertical: pad > 0 ? pad : AppSpacing.s48),
              itemCount: lyrics.lines.length,
              itemBuilder: (context, index) {
                final line = lyrics.lines[index];
                final isCurrent = index == currentIndex;
                return SizedBox(
                  height: _lineHeight,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s16),
                      child: AnimatedDefaultTextStyle(
                        // 当前行字号/字重/颜色平滑过渡
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        style: TextStyle(
                          fontSize: isCurrent ? 18 : 14,
                          fontWeight:
                              isCurrent ? FontWeight.w600 : FontWeight.normal,
                          color: isCurrent ? cs.primary : cs.onSurfaceVariant,
                        ),
                        child: Text(
                          line.text.isEmpty ? '♪' : line.text,
                          textAlign: TextAlign.center,
                          // 长句允许两行，避免被直接截断
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

/// Widget 预览：同步歌词（有歌词，当前高亮第 2 行）
@Preview(name: 'LyricsView 有歌词', group: 'LyricsView')
Widget lyricsViewPreview() {
  const lines = [
    LyricLine(time: Duration(seconds: 0), text: '故事的小黄花'),
    LyricLine(time: Duration(seconds: 4), text: '从出生那年就飘着'),
    LyricLine(time: Duration(seconds: 8), text: '童年的荡秋千'),
    LyricLine(time: Duration(seconds: 12), text: '随记忆一直晃到现在'),
  ];
  // 用预置歌词的 Notifier 覆盖 lyricsProvider，避免直接写 state
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWith((ref) => InMemoryDatabaseProvider()),
    lyricsProvider.overrideWith(
      () => _PreviewLyricsNotifier(
        Lyrics(songId: '1', sourceId: 'netease', lines: lines),
      ),
    ),
  ]);
  container
      .read(playbackPositionProvider.notifier)
      .setPosition(const Duration(seconds: 5));

  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: LyricsView())),
  );
}

/// Widget 预览：无歌词
@Preview(name: 'LyricsView 无歌词', group: 'LyricsView')
Widget lyricsViewEmptyPreview() {
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWith((ref) => InMemoryDatabaseProvider()),
    lyricsProvider.overrideWith(() => _PreviewLyricsNotifier(null)),
  ]);
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: LyricsView())),
  );
}

/// 预览用歌词 Notifier：build 直接返回固定歌词，不依赖源管理器
class _PreviewLyricsNotifier extends LyricsNotifier {
  final Lyrics? _lyrics;

  _PreviewLyricsNotifier(this._lyrics);

  @override
  Lyrics? build() => _lyrics;
}
