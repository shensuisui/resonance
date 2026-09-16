/// 同步歌词视图
///
/// 根据播放进度高亮当前歌词行并自动滚动居中。
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。
library;

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../providers/providers.dart';
import '../theme/app_spacing.dart';

class LyricsView extends ConsumerStatefulWidget {
  const LyricsView({super.key});

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  final _scrollController = ScrollController();
  final _lineHeight = 44.0;

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

    if (lyrics == null) {
      return Center(
        child: Text('暂无歌词', style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }

    final currentIndex = _currentIndex(lyrics.lines, position);

    // 高亮行滚动到可视区中部（用 addPostFrameCallback 避免 build 期间动 scroll）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (currentIndex < 0) return;
      final target = currentIndex * _lineHeight;
      final offset = _scrollController.offset;
      if ((target - offset).abs() > 2) {
        _scrollController.animateTo(
          target.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s48),
      itemCount: lyrics.lines.length,
      itemBuilder: (context, index) {
        final line = lyrics.lines[index];
        final isCurrent = index == currentIndex;
        return SizedBox(
          height: _lineHeight,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
              child: Text(
                line.text.isEmpty ? '♪' : line.text,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isCurrent ? 18 : 14,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                  color: isCurrent ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
      },
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
