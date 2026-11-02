/// 我喜欢的音乐（原型 renderLiked / likedBody）
///
/// hero（拼贴封面 + 统计 + 播放全部 / 随机播放 / 加入队列）+ 排序 chip + 曲目面板。
/// 数据是真实收藏：[likedSongsProvider]（FavoritesDao 的快照记录 → [Song]）；
/// 时长在快照里没有，用展示元数据（[catalogTracksProvider]）补齐。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/hero.dart';
import '../components/rows.dart';
import '../components/sheets.dart';
import '../components/surfaces.dart';
import '../data/catalog.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../providers/providers.dart';
import '../router.dart';
import '../widgets/page_shell.dart';
import '../widgets/track_actions.dart';

/// 我喜欢的音乐
class LikedPage extends ConsumerStatefulWidget {
  /// 构造页面
  const LikedPage({super.key});

  @override
  ConsumerState<LikedPage> createState() => _LikedPageState();
}

class _LikedPageState extends ConsumerState<LikedPage> {
  LikedSort _sort = LikedSort.recent;

  @override
  Widget build(BuildContext context) {
    // 真实收藏：FavoritesDao 记录（新→旧）还原成 Song，标题/歌手/封面来自写入时的快照
    final songs = ref.watch(likedSongsProvider);
    // 展示元数据：只有快照没给时长时用来兜底
    final meta = ref.watch(catalogTracksProvider);

    /// 曲目时长（秒）：快照 → 配表 → 元数据缓存（统一回落，含播放器实测回写）
    int durationOf(Song song) =>
        resolveSongDuration(ref, song, catalogDuration: meta[song.id]?.duration);

    if (songs.isEmpty) {
      return PageShell(
        topPadding: UiV2Spacing.s4,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageHead(title: '我喜欢的音乐', sub: '自动同步在线与本地曲目'),
            UiV2Panel(
              child: UiV2Empty(
                title: '还没有喜欢的歌曲',
                text: '在任何歌曲上点一下爱心，就会出现在这里。你可以在首页或搜索里找歌。',
                icon: UiV2Icons.heart,
                actions: UiV2Button(
                  label: '去首页看看',
                  variant: UiV2ButtonVariant.soft,
                  onTap: () => ref.read(navProvider.notifier).go('home'),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // DAO 顺序本身就是「最近喜欢」（新→旧），不需要再反转
    final ordered = switch (_sort) {
      LikedSort.recent => songs,
      LikedSort.title => (List.of(songs)
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()))),
      LikedSort.duration => (List.of(songs)
        ..sort((a, b) => durationOf(b).compareTo(durationOf(a)))),
    };

    final count = songs.length;
    final totalSec = songs.fold<int>(0, (sum, song) => sum + durationOf(song));
    final totalText = formatDurationLong(totalSec);
    // 「本地」= 真实带缓存路径的曲目（本地扫描或已下载）
    final localCount =
        songs.where((song) => (song.localPath ?? '').isNotEmpty).length;
    final onlineCount = count - localCount;
    // 手机（< 768）用精简头部：与歌单详情同款排布 —— 封面与文字左右并排，
    // 标题已在顶部标题栏，统计与按钮挤在封面右侧，高度由封面决定。
    final compact = MediaQuery.sizeOf(context).width < UiV2Breakpoints.wide;
    final queue = TrackActions.likedQueue(ordered);
    final actions = <Widget>[
      UiV2Button(
        key: const ValueKey('liked_play_all'),
        label: '播放全部',
        icon: UiV2Icons.play,
        variant: UiV2ButtonVariant.primary,
        compact: compact,
        onTap: () => TrackActions.playQueueAll(context, ref, queue),
      ),
      UiV2Button(
        key: const ValueKey('liked_shuffle'),
        label: '随机播放',
        icon: UiV2Icons.shuffle,
        variant: UiV2ButtonVariant.soft,
        compact: compact,
        onTap: () => TrackActions.shuffleQueueAll(context, ref, queue),
      ),
    ];
    final statLine = '$count 首 · $totalText';
    final statLine2 = '在线 $onlineCount 首 · 本地 $localCount 首';

    return PageShell(
      // 手机端头部已经很矮，上边距也收紧一点，把高度让给曲目列表
      topPadding: compact ? UiV2Spacing.s2 : UiV2Spacing.s4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compact)
            _compactHeader(
              context,
              type: '收藏',
              statLine: statLine,
              statLine2: statLine2,
              actions: actions,
            )
          else
            UiV2Hero(
              // 收藏页不再拼贴随机曲目封面：那和「喜欢」这件事本身没关系，
              // 固定一颗实心红心，一眼就知道这一页是什么
              art: const LikedHeartArt(),
              type: '收藏',
              title: '我喜欢的音乐',
              meta: '$count 首 · $totalText · 在线 $onlineCount 首 · 本地 $localCount 首',
              actions: actions,
            ),
          UiV2FilterRail(
            margin: const EdgeInsets.only(bottom: UiV2Spacing.s5),
            children: [
              for (final sort in LikedSort.values)
                UiV2Chip(
                  label: sort.label,
                  selected: _sort == sort,
                  onTap: () => setState(() => _sort = sort),
                ),
            ],
          ),
          UiV2Panel(
            child: UiV2TrackList(
              rows: [
                for (var i = 0; i < ordered.length; i++)
                  UiV2SongRow(
                    song: ordered[i],
                    meta: meta[ordered[i].id],
                    index: i,
                    showArt: true,
                    queueIdentity: 'liked',
                    onTap: () => TrackActions.playInQueue(
                        context, ref, TrackActions.likedQueue(ordered), i),
                    onToggleLike: () =>
                        TrackActions.toggleLike(context, ref, ordered[i]),
                    onMore: () =>
                        showTrackMenu(context, song: ordered[i]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  /// 手机端精简头部（与歌单详情同款排布）
  ///
  /// 靠**改排布**降高度：封面与文字左右并排，页面标题已在顶部标题栏，
  /// 统计两行与按钮挤在封面右侧 —— 不再在封面下面再堆「标题 + 统计 + 按钮」那一段。
  /// 按钮用 [Wrap]：窄屏（360）右侧只剩约 110px，两个按钮放不下时自动换行，
  /// 不会溢出；高度仍由封面（220）决定。
  Widget _compactHeader(
    BuildContext context, {
    required String type,
    required String statLine,
    required String statLine2,
    required List<Widget> actions,
  }) {
    final t = UiV2Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    // 与 UiV2Hero / 歌单详情的窄屏封面尺寸保持一致，不缩小
    final artSize = (width * 0.56).clamp(120.0, 220.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: UiV2Spacing.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: artSize,
            height: artSize,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: UiV2Radii.brLg,
                boxShadow: t.shadow3,
                color: t.surface2,
              ),
              child: ClipRRect(
                borderRadius: UiV2Radii.brLg,
                child: const LikedHeartArt(),
              ),
            ),
          ),
          const SizedBox(width: UiV2Spacing.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  type,
                  style: UiV2Text.capsLabel.copyWith(color: t.textDim),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: UiV2Spacing.s2),
                Text(
                  statLine,
                  style: UiV2Text.bodyDim.copyWith(color: t.textDim),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  statLine2,
                  style: UiV2Text.hint.copyWith(color: t.textDim),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: UiV2Spacing.s3),
                Wrap(
                  spacing: UiV2Spacing.s2,
                  runSpacing: UiV2Spacing.s2,
                  children: actions,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 「我喜欢的音乐」的固定封面：浅粉底 + 实心红心
///
/// 不再拼贴随机曲目的封面 —— 那和「喜欢」本身没关系；固定一颗实心红心，
/// 与歌单封面（拼贴）在视觉上区分开，一眼就知道这一页是收藏。
class LikedHeartArt extends StatelessWidget {
  /// 心形边长相对封面边长的占比
  final double iconRatio;

  /// 构造收藏封面
  const LikedHeartArt({super.key, this.iconRatio = 0.38});

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final side = c.biggest.shortestSide;
        return ColoredBox(
          // 显式合成不透明底色：accentSoft2 本身是半透明，直接铺会依赖父级底色
          color: Color.alphaBlend(t.accentSoft2, t.surface2),
          child: Center(
            child: UiV2Icon(
              UiV2Icons.heartFill,
              size: side * iconRatio,
              color: t.accent,
            ),
          ),
        );
      },
    );
  }
}
