/// 沉浸播放页（.nowplaying）—— 大封面 / 歌词舞台 + 信息与控件面板。
///
/// 断点行为：≤1023 单列纵向居中；≥1024 两列（封面/歌词 ｜ 面板），封面宽度上限 420。
/// 收起交互：顶部下箭头或下滑手势；Escape 亦可（Flutter 侧由 PopScope 处理）。
library;

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalog.dart';
import '../data/lyrics.dart';
import '../design/icons.dart';
import '../design/network_image.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../providers/providers.dart';
import 'player_bar.dart';
import 'rows.dart';
import 'sheets.dart';

/// 沉浸播放页外壳（含展开/收起动画）
class UiV2NowPlayingOverlay extends ConsumerStatefulWidget {
  /// 构造覆盖层
  const UiV2NowPlayingOverlay({super.key});

  @override
  ConsumerState<UiV2NowPlayingOverlay> createState() =>
      _UiV2NowPlayingOverlayState();
}

class _UiV2NowPlayingOverlayState extends ConsumerState<UiV2NowPlayingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: UiV2Motion.d3,
    value: ref.read(nowPlayingProvider) ? 1 : 0,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = ref.watch(nowPlayingProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (open) {
        if (_controller.value < 1 &&
            _controller.status != AnimationStatus.forward) {
          _controller.forward();
        }
      } else if (_controller.value > 0 &&
          _controller.status != AnimationStatus.reverse) {
        _controller.reverse();
      }
    });

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.value == 0) return const SizedBox.shrink();
        final slide = Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        )
            .animate(CurvedAnimation(
              parent: _controller,
              curve: UiV2Motion.enter,
              reverseCurve: UiV2Motion.exit,
            ))
            .value;
        return Positioned.fill(
          child: FractionalTranslation(
            translation: slide,
            child: const UiV2NowPlayingScreen(),
          ),
        );
      },
    );
  }
}

/// 沉浸播放页内容
class UiV2NowPlayingScreen extends ConsumerWidget {
  /// 构造内容
  const UiV2NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final gutter = _gutterFor(width);
    final song = ref.watch(currentSongProvider);
    final meta = song == null ? null : ref.watch(catalogTracksProvider)[song.id];
    final cover = song == null
        ? null
        : resolveSongCover(ref, song, catalogCover: meta?.cover);

    return Material(
      color: t.bg,
      child: GestureDetector(
        onVerticalDragEnd: (details) {
          // 下滑收起（原型的收起入口是顶部箭头，这里额外支持下拉手势）
          if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
            ref.read(nowPlayingProvider.notifier).close();
          }
        },
        child: Stack(
          children: [
            // 背景：封面放大 + 模糊 + 暗化渐变
            Positioned.fill(
              child: _Background(
                cover: cover,
                tokens: t,
                headers: uiV2ImageHeadersFor(ref, song?.sourceId),
              ),
            ),
            Positioned.fill(
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: UiV2Metrics.nowPlayingMax,
                    ),
                    child: Padding(
                      // 底部除了安全域再留一点间距：工具行（歌词/队列/睡眠/设备）
                      // 紧贴屏幕下缘很难看（用户指出）
                      padding: EdgeInsets.fromLTRB(
                        gutter,
                        0,
                        gutter,
                        UiV2Spacing.s4,
                      ),
                      child: Column(
                        children: [
                          const _TopRow(),
                          Expanded(
                            child: width >= UiV2Breakpoints.desktop
                                ? _WideBody(gutter: gutter)
                                : _CompactBody(gutter: gutter),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 页面左右留白（--gutter：16 / 24 / 32 / 40）
  static double _gutterFor(double width) {
    if (width >= UiV2Breakpoints.large) return 40;
    if (width >= UiV2Breakpoints.desktop) return 32;
    if (width >= UiV2Breakpoints.wide) return 24;
    return 16;
  }
}

/// 背景层（.np__bg）
class _Background extends StatelessWidget {
  final String? cover;

  /// 图片请求头
  final Map<String, String> headers;
  final UiV2Tokens tokens;

  const _Background({
    required this.cover,
    required this.tokens,
    this.headers = const <String, String>{},
  });

  /// 该曲目来源的图片请求头（枫叶需要 referer）

  @override
  Widget build(BuildContext context) {
    final hasCover = cover != null && cover!.isNotEmpty;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasCover)
            Opacity(
              opacity: tokens.isDark ? 0.5 : 0.32,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
                child: Transform.scale(
                  scale: 1.25,
                  child: cover!.startsWith('assets/')
                      ? Image.asset(cover!, fit: BoxFit.cover)
                      : UiV2NetworkImage(url: cover!, headers: headers),
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: tokens.isDark
                    ? [tokens.scrim2, tokens.scrim, tokens.bg]
                    : [
                        tokens.bg.withValues(alpha: 0.7),
                        tokens.bg.withValues(alpha: 0.92),
                        tokens.bg,
                      ],
                stops: tokens.isDark ? const [0, 0.4, 1] : const [0, 0.45, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 播放页顶部「正在播放」下面那一行
///
/// 用户要求这里显示**播放队列的名字**（默认1 / 最近播放 / 我喜欢的音乐…），
/// 这样一眼能看出"当前这轮播放属于哪个队列"；有睡眠倒计时时并列显示。
/// 没有队列（还没播过任何东西）才退回占位符。
String nowPlayingContextLine({
  required bool pending,
  required String queueTitle,
  required bool hasQueue,
  required Duration? sleep,
}) {
  if (pending) return '准备播放中';
  final parts = <String>[
    if (hasQueue && queueTitle.isNotEmpty) queueTitle,
    if (sleep != null) '睡眠 ' + formatDuration(sleep.inSeconds),
  ];
  return parts.isEmpty ? '—' : parts.join(' · ');
}

/// 顶部行（.np__top）：收起、上下文、更多
class _TopRow extends ConsumerWidget {
  const _TopRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final song = ref.watch(currentSongProvider);
    final pending = ref.watch(pendingProvider) != null;
    final sleep = ref.watch(sleepTimerProvider);

    final contextLine = nowPlayingContextLine(
      pending: pending,
      queueTitle: ref.watch(queueProvider).title,
      hasQueue: !ref.watch(queueProvider).isEmpty,
      sleep: sleep,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: UiV2Spacing.s3),
      child: Row(
        children: [
          UiV2IconButton(
            key: const ValueKey('np_close'),
            icon: UiV2Icons.chevronDown,
            semanticLabel: '收起播放页',
            onTap: () => ref.read(nowPlayingProvider.notifier).close(),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '正在播放',
                  style: UiV2Text.capsLabelSmall.copyWith(color: t.textDim),
                ),
                Text(
                  contextLine,
                  style: UiV2Text.buttonSmall.copyWith(color: t.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          UiV2IconButton(
            icon: UiV2Icons.more,
            semanticLabel: '更多操作',
            onTap: song == null
                ? () => showUiV2Toast(context, '先挑一首歌')
                : () => showTrackMenu(context),
          ),
        ],
      ),
    );
  }
}

/// 窄屏主体（≤1023）：舞台 + 面板纵向排列
///
/// **整页不滚**（用户要求）：以前是 SingleChildScrollView，手机上稍微一推就整页滑。
/// 现在按可用高度分配：面板先占它需要的高度，剩下的全给正方形舞台（封面/歌词），
/// 舞台因此会自动缩成正方形而不会顶出去。
/// 极端情况（窗口被拉得很扁）用 FittedBox 等比缩小，也不再出现滚动条。
class _CompactBody extends StatelessWidget {
  final double gutter;

  const _CompactBody({required this.gutter});

  /// 面板（标题/进度/主控/工具行）压紧后的高度上界
  ///
  /// 故意取比实际略大的值：宁可舞台小 2px，也不要因为估少了而溢出。
  static const double _panelEstimate = 252;

  /// 舞台的最小可用高度（再小就整体等比缩小）
  static const double _stageMin = 140;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final gap = UiV2Spacing.s3;
        final room = c.maxHeight - _panelEstimate - gap;
        if (room < _stageMin) {
          // 极端小窗：按"刚好放得下"的设计尺寸整体等比缩放（不会裁切、不会滚）
          final designHeight = _panelEstimate + _stageMin + gap;
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: c.maxWidth,
              height: designHeight,
              child: _layout(c.maxWidth, _stageMin, gap),
            ),
          );
        }
        return _layout(c.maxWidth, math.min(c.maxWidth, room), gap);
      },
    );
  }

  /// 固定高度的两段式布局：舞台（正方形）+ 面板
  Widget _layout(double width, double stageSize, double gap) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SizedBox(
              width: stageSize,
              height: stageSize,
              child: const _Stage(),
            ),
          ),
        ),
        SizedBox(height: gap),
        const _Panel(tight: true),
      ],
    );
  }
}

/// 宽屏主体（≥1024）：两列
class _WideBody extends StatelessWidget {
  final double gutter;

  const _WideBody({required this.gutter});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: const AspectRatio(aspectRatio: 1, child: _Stage()),
            ),
          ),
        ),
        const SizedBox(width: UiV2Spacing.s8),
        Expanded(child: SingleChildScrollView(child: const _Panel())),
      ],
    );
  }
}

/// 舞台（.np__art）：封面与歌词共用同一个正方形盒子
class _Stage extends ConsumerStatefulWidget {
  const _Stage();

  @override
  ConsumerState<_Stage> createState() => _StageState();
}

class _StageState extends ConsumerState<_Stage> {
  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final song = ref.watch(currentSongProvider);
    final lyricsOpen = ref.watch(lyricsOpenProvider);
    final pending = ref.watch(pendingProvider) != null;
    final meta = song == null ? null : ref.watch(catalogTracksProvider)[song.id];
    final cover = song == null
        ? null
        : resolveSongCover(ref, song, catalogCover: meta?.cover);
    final showLyrics = lyricsOpen && song != null;

    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surface2,
          borderRadius: UiV2Radii.brXl,
          boxShadow: t.shadow3,
        ),
        child: ClipRRect(
          borderRadius: UiV2Radii.brXl,
          child: showLyrics
              ? const UiV2LyricsStage()
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    if (cover != null && cover.isNotEmpty)
                      cover.startsWith('assets/')
                          ? Image.asset(cover, fit: BoxFit.cover)
                          : UiV2NetworkImage(
                              url: cover,
                              headers: uiV2ImageHeadersFor(ref, song?.sourceId),
                            )
                    else
                      Center(
                        child: UiV2Icon(
                          UiV2Icons.note,
                          size: 56,
                          color: t.textMute,
                        ),
                      ),
                    // 无曲目时的引导文案（原型 .np__art-empty）
                    if (song == null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: UiV2Spacing.s5,
                        child: Text(
                          '从首页或音乐库挑一首',
                          textAlign: TextAlign.center,
                          style: UiV2Text.hint.copyWith(color: t.textDim),
                        ),
                      ),
                    if (pending)
                      Container(
                        color: const Color(0x8C060709),
                        alignment: Alignment.center,
                        child: UiV2Spinner(
                          trackColor: const Color(0x57FFFFFF),
                          color: const Color(0xFFFFFFFF),
                          size: 28,
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// 歌词舞台（.np__lyrics）：注记 + 可滚动词条，当前行高亮并居中
class UiV2LyricsStage extends ConsumerStatefulWidget {
  /// 构造歌词舞台
  const UiV2LyricsStage({super.key});

  @override
  ConsumerState<UiV2LyricsStage> createState() => _UiV2LyricsStageState();
}

class _UiV2LyricsStageState extends ConsumerState<UiV2LyricsStage> {
  final ScrollController _scroll = ScrollController();
  final List<GlobalKey> _keys = [];

  /// 舞台根节点的上下文（用于把歌词行坐标换算到滚动容器坐标系）
  BuildContext? _stageContext;
  int _active = -1;
  String? _builtFor;
  LyricScript _script = const LyricScript(source: LyricSource.none, entries: []);
  bool _follow = true;
  DateTime _lastUserScroll = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final song = ref.watch(currentSongProvider);
    final fromSource = ref.watch(lyricsProvider);
    if (song == null) {
      return const SizedBox.shrink();
    }

    // 展示元数据（演示曲库曲目才有）；真实源曲目直接用 Song 自身字段
    final meta = ref.watch(catalogTracksProvider)[song.id];
    // 时长统一回落（配表 → 快照 → 元数据缓存）；仍拿不到时按 3 分钟兜底
    final resolved = resolveSongDuration(ref, song, catalogDuration: meta?.duration);
    final duration = resolved > 0 ? resolved : 180;
    _stageContext = context;
    if (_builtFor != song.id || fromSource != null) {
      _builtFor = song.id;
      _script = buildLyricScript(
        trackId: song.id,
        durationSeconds: duration,
        fromSource: fromSource,
      );
      // _script 按曲目重建后，行 key 与活动行都要复位
      _follow = true;
      _keys
        ..clear()
        ..addAll(List.generate(_script.entries.length, (_) => GlobalKey()));
      _active = -1;
    }

    final position = ref.watch(positionProvider);
    final active = activeLyricIndex(_script.entries, position);
    if (active != _active) {
      _active = active;
      if (_follow) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
      }
    }

    if (!_script.hasLyrics) {
      return Padding(
        padding: const EdgeInsets.all(UiV2Spacing.s5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            UiV2Icon(UiV2Icons.lyrics, size: 40, color: t.textMute),
            const SizedBox(height: UiV2Spacing.s2),
            Text('这首歌的来源没有提供歌词', style: UiV2Text.emptyTitle.copyWith(color: t.text)),
            const SizedBox(height: UiV2Spacing.s2),
            Text(
              '内置曲目使用原创演示文本，本地扫描的曲目会读取同名的 .lrc 文件；两者都没有时显示这里。',
              textAlign: TextAlign.center,
              style: UiV2Text.hint.copyWith(color: t.textDim),
            ),
          ],
        ),
      );
    }

    final note = _script.source == LyricSource.lrc
        ? '来自同名 .lrc 文件'
        : kLyricsNote;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            UiV2Spacing.s4,
            UiV2Spacing.s3,
            UiV2Spacing.s4,
            UiV2Spacing.s2,
          ),
          child: Text(
            note,
            style: UiV2Text.capsLabelSmall.copyWith(color: t.textMute),
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null) {
                _follow = false;
                _lastUserScroll = DateTime.now();
              }
              if (notification is ScrollEndNotification && !_follow) {
                // 停手 4 秒后恢复跟随（原型 lyricsFollowTimer）
                Future<void>.delayed(const Duration(seconds: 4), () {
                  if (!mounted) return;
                  if (DateTime.now().difference(_lastUserScroll) <
                      const Duration(seconds: 4)) {
                    return;
                  }
                  setState(() => _follow = true);
                  _scrollToActive();
                });
              }
              return false;
            },
            child: ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x00000000),
                  Color(0xFF000000),
                  Color(0xFF000000),
                  Color(0x00000000),
                ],
                stops: [0, 0.06, 0.94, 1],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(
                  horizontal: UiV2Spacing.s4,
                  vertical: UiV2Spacing.s4,
                ),
                itemCount: _script.entries.length,
                itemBuilder: (context, index) {
                  final entry = _script.entries[index];
                  final isActive = index == _active;
                  return Container(
                    key: _keys[index],
                    padding: EdgeInsets.only(
                      left: UiV2Spacing.s3,
                      top: entry.isGap ? 0 : 2,
                      bottom: entry.isGap ? UiV2Spacing.s3 : 2,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          width: 2,
                          color: isActive ? t.accent : const Color(0x00000000),
                        ),
                      ),
                    ),
                    child: AnimatedSlide(
                      duration: UiV2Motion.d2,
                      curve: UiV2Motion.enter,
                      offset: isActive ? const Offset(0.012, 0) : Offset.zero,
                      child: AnimatedDefaultTextStyle(
                        duration: UiV2Motion.d2,
                        curve: UiV2Motion.enter,
                        style: UiV2Text.lyrics.copyWith(
                          color: isActive ? t.accent : t.textMute,
                        ),
                        child: Text(entry.text.isEmpty ? ' ' : entry.text),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 把当前行滚到容器中心（等价原型 scrollLyricsTo 的居中 + clamp）
  void _scrollToActive() {
    if (_active < 0 || _active >= _keys.length || !_scroll.hasClients) return;
    final ctx = _keys[_active].currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox) return;
    final viewport = _scroll.position.viewportDimension;
    final ancestor = _stageContext?.findRenderObject();
    if (ancestor == null) return;
    final offset = box.localToGlobal(Offset.zero, ancestor: ancestor).dy;
    final target = (_scroll.offset + offset - (viewport - box.size.height) / 2)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: UiV2Motion.enter,
    );
  }
}

/// 信息与控件面板（.np__panelcol）
class _Panel extends ConsumerWidget {
  /// 是否压紧（窄屏用：标题只留一行、各段间距收窄，把高度让给封面）
  final bool tight;

  const _Panel({this.tight = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < UiV2Breakpoints.wide;
    final small = width < UiV2Breakpoints.wide;
    final song = ref.watch(currentSongProvider);
    final lyricsOpen = ref.watch(lyricsOpenProvider);
    final sleep = ref.watch(sleepTimerProvider);
    // 压紧模式（窄屏）：各段间距从 s5 收到 s3，标题只留一行
    final gap = tight ? UiV2Spacing.s3 : UiV2Spacing.s5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song?.title ?? '未在播放',
                    style: UiV2Text.npTitle.copyWith(color: t.text),
                    maxLines: tight ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    song?.artist ?? '从首页或音乐库挑一首',
                    style: UiV2Text.bodyDim.copyWith(color: t.textDim),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: UiV2Spacing.s4),
            _LikeToggle(song: song),
          ],
        ),
        SizedBox(height: gap),
        const UiV2ProgressBar(
          stacked: true,
          trackHeight: 24,
          barHeight: 5,
          thumbSize: 14,
        ),
        SizedBox(height: gap),
        UiV2Transport(buttonSize: 48, largePlay: true, spread: true),
        SizedBox(height: gap),
        Row(
          mainAxisAlignment:
              compact ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
          children: [
            UiV2IconButton(
              key: const ValueKey('np_lyrics'),
              icon: UiV2Icons.lyrics,
              semanticLabel: lyricsOpen ? '收起歌词' : '歌词',
              pressed: lyricsOpen,
              onTap: song == null
                  ? () => showUiV2Toast(context, '先挑一首歌')
                  : () => ref.read(lyricsOpenProvider.notifier).toggle(),
            ),
            const SizedBox(width: UiV2Spacing.s2),
            UiV2IconButton(
              icon: UiV2Icons.queue,
              semanticLabel: '播放队列',
              onTap: () => showQueueSheet(context),
            ),
            const SizedBox(width: UiV2Spacing.s2),
            UiV2IconButton(
              key: const ValueKey('np_sleep'),
              icon: UiV2Icons.clock,
              semanticLabel: '睡眠定时器',
              pressed: sleep != null,
              onTap: () => showSleepSheet(context),
            ),
            const SizedBox(width: UiV2Spacing.s2),
            UiV2IconButton(
              icon: UiV2Icons.device,
              semanticLabel: '播放设备',
              onTap: () => showDeviceSheet(context),
            ),
            if (!small) ...[
              const SizedBox(width: UiV2Spacing.s2),
              _MuteToggle(),
              const SizedBox(width: UiV2Spacing.s2),
              const UiV2VolumeSlider(),
            ],
          ],
        ),
      ],
    );
  }
}

/// 沉浸页爱心
class _LikeToggle extends ConsumerWidget {
  /// 当前曲目（null 表示未在播放 → 按钮禁用）
  final Song? song;

  /// 构造收藏按钮
  const _LikeToggle({required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final liked = ref.watch(likedProvider);
    final key = song?.globalKey;
    final isLiked = key != null && liked.any((r) => r.songKey == key);
    return UiV2IconButton(
      icon: isLiked ? UiV2Icons.heartFill : UiV2Icons.heart,
      semanticLabel: isLiked ? '取消喜欢' : '喜欢',
      color: isLiked ? t.accent : t.textDim,
      disabled: song == null,
      onTap: song == null
          ? null
          : () async {
              final target = song;
              if (target == null) return;
              await ref.read(likedProvider.notifier).toggle(target);
              if (context.mounted) {
                showUiV2Toast(
                  context,
                  isLiked ? '已从「我喜欢的音乐」移除' : '已加入「我喜欢的音乐」',
                );
              }
            },
    );
  }
}

/// 沉浸页静音键
class _MuteToggle extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volume = ref.watch(volumeProvider);
    return UiV2IconButton(
      icon: volume.muted ? UiV2Icons.volumeMute : UiV2Icons.volume,
      semanticLabel: '静音',
      pressed: volume.muted,
      onTap: () async {
        await ref.read(volumeProvider.notifier).toggleMute();
        if (context.mounted) {
          final next = ref.read(volumeProvider);
          showUiV2Toast(
            context,
            next.muted ? '已静音' : '音量 ${(next.volume * 100).round()}%',
          );
        }
      },
    );
  }
}
