/// 播放条（.playerbar）与共享播放控件（进度条 / 音量条）。
///
/// 三区结构与原型一致：
///   移动端（≤767）：[封面 + 歌名/艺人 + 爱心] + [上一/播放/下一]，顶部 2px 细线进度
///   宽屏（≥768）：[封面 + 歌名 + 爱心] ｜ [控件行 + 进度条] ｜ [音量 下载 队列 展开]
///   平板（768–1180）：第一区只留封面，收藏移到控件行首位，音量整组隐藏
library;

import 'dart:ui' show ImageFilter;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalog.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../providers/providers.dart';
import '../router.dart';
import 'rows.dart';
import 'sheets.dart';

/// 进度条（.progress + .progress--bar / .progress--np）
///
/// 点击 / 拖动定位：按指针在轨道上的比例 seek（等价原型 click 定位 + 键盘方向键）。
class UiV2ProgressBar extends ConsumerStatefulWidget {
  /// 是否显示左右时间（沉浸页为 true，播放条为 true）
  final bool showTimes;

  /// 轨道高度（播放条 20，沉浸页 24）
  final double trackHeight;

  /// 进度条高度（4 / 5）
  final double barHeight;

  /// 滑块直径（12 / 14）
  final double thumbSize;

  /// 时间与轨道的排布（沉浸页为上下两行）
  final bool stacked;

  /// 构造进度条
  const UiV2ProgressBar({
    super.key,
    this.showTimes = true,
    this.trackHeight = 20,
    this.barHeight = 4,
    this.thumbSize = 12,
    this.stacked = false,
  });

  @override
  ConsumerState<UiV2ProgressBar> createState() => _UiV2ProgressBarState();
}

class _UiV2ProgressBarState extends ConsumerState<UiV2ProgressBar> {
  bool _dragging = false;
  bool _hover = false;
  double _dragRatio = 0;

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final position = ref.watch(positionProvider);
    final duration = ref.watch(durationProvider);
    final total = duration.inMilliseconds;
    final current = _dragging
        ? Duration(milliseconds: (total * _dragRatio).round())
        : position;
    final ratio = total <= 0 ? 0.0 : (current.inMilliseconds / total).clamp(0.0, 1.0);

    final track = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // 滑块行程按直径内缩：中心只能在 [半径, width-半径] 之间。
        // 不内缩的话 ratio=1 时滑块右缘会超出 width 半径那么远，被 Stack 裁成一条竖边。
        final thumbRadius = widget.thumbSize / 2;
        // 轨道可视宽度 = 盒子宽度 − 一个滑块直径（左右各缩进半个滑块）
        final trackWidth = (width - widget.thumbSize).clamp(0.0, double.infinity);
        double ratioForDx(double dx) =>
            trackWidth <= 0 ? 0.0 : ((dx - thumbRadius) / trackWidth).clamp(0.0, 1.0);
        void seekTo(double dx) {
          final value = ratioForDx(dx);
          setState(() => _dragRatio = value);
          ref.read(playbackControllerProvider).seekRatio(value);
        }

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => seekTo(d.localPosition.dx),
            onHorizontalDragStart: (d) {
              setState(() {
                _dragging = true;
                _dragRatio = ratioForDx(d.localPosition.dx);
              });
            },
            onHorizontalDragUpdate: (d) => setState(
              () => _dragRatio = ratioForDx(d.localPosition.dx),
            ),
            onHorizontalDragEnd: (_) {
              final r = _dragRatio;
              setState(() => _dragging = false);
              ref.read(playbackControllerProvider).seekRatio(r);
            },
            child: SizedBox(
              height: widget.trackHeight,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // 轨道左右各缩进半个滑块：轨道两端就是 0% / 100%，
                  // 滑块走到端点正好压在轨道末端（既不会短一截，也不会画到框外被裁）
                  Positioned(
                    left: thumbRadius,
                    right: thumbRadius,
                    child: Container(
                      height: widget.barHeight,
                      decoration: BoxDecoration(
                        color: t.surface3,
                        borderRadius: UiV2Radii.brPill,
                      ),
                    ),
                  ),
                  Positioned(
                    left: thumbRadius,
                    right: thumbRadius,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: ratio,
                      child: Container(
                        height: widget.barHeight,
                        decoration: BoxDecoration(
                          color: t.accent,
                          borderRadius: UiV2Radii.brPill,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: ratio * trackWidth,
                    child: AnimatedOpacity(
                      duration: UiV2Motion.d1,
                      curve: UiV2Motion.enter,
                      opacity: (_hover || _dragging) ? 1 : 0,
                      child: Container(
                        width: widget.thumbSize,
                        height: widget.thumbSize,
                        decoration: BoxDecoration(
                          color: t.text,
                          borderRadius: UiV2Radii.brPill,
                          boxShadow: t.shadow1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!widget.showTimes) return track;

    final times = Row(
      mainAxisAlignment: widget.stacked
          ? MainAxisAlignment.spaceBetween
          : MainAxisAlignment.center,
      children: [
        Text(
          formatDuration(current.inSeconds),
          style: UiV2Text.progressTime.copyWith(color: t.textMute),
        ),
        Text(
          formatDuration(duration.inSeconds),
          style: UiV2Text.progressTime.copyWith(color: t.textMute),
        ),
      ],
    );

    if (widget.stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          track,
          const SizedBox(height: UiV2Spacing.s2),
          times,
        ],
      );
    }

    return Row(
      children: [
        Text(
          formatDuration(current.inSeconds),
          style: UiV2Text.progressTime.copyWith(color: t.textMute),
        ),
        const SizedBox(width: UiV2Spacing.s3),
        Expanded(child: track),
        const SizedBox(width: UiV2Spacing.s3),
        Text(
          formatDuration(duration.inSeconds),
          style: UiV2Text.progressTime.copyWith(color: t.textMute),
        ),
      ],
    );
  }
}

/// 音量条（.volume__range）：104×20，4px 轨道 + 12px 滑块
class UiV2VolumeSlider extends ConsumerWidget {
  /// 轨道宽度（默认 104）
  final double width;

  /// 构造音量条
  const UiV2VolumeSlider({super.key, this.width = 104});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final volume = ref.watch(volumeProvider);
    return SizedBox(
      width: width,
      height: 20,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          // 同进度条：滑块行程按直径内缩，满值时右缘才不会被 Stack 裁成竖条
          const thumb = 12.0;
          double volumeForDx(double dx) =>
              ((dx - thumb / 2) / (w - thumb)).clamp(0.0, 1.0);
          void setFromDx(double dx) =>
              ref.read(volumeProvider.notifier).setVolume(volumeForDx(dx));
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => setFromDx(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => setFromDx(d.localPosition.dx),
            child: Semantics(
              label: '音量',
              slider: true,
              value: '${(volume.volume * 100).round()}%',
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // 同进度条：轨道内缩半个滑块，滑块满行程且不出框
                  Positioned(
                    left: thumb / 2,
                    right: thumb / 2,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: t.surface3,
                        borderRadius: UiV2Radii.brPill,
                      ),
                    ),
                  ),
                  Positioned(
                    left: thumb / 2,
                    right: thumb / 2,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: volume.volume.clamp(0.0, 1.0),
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: t.accent,
                          borderRadius: UiV2Radii.brPill,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: volume.volume.clamp(0.0, 1.0) * (w - thumb),
                    child: Container(
                      width: thumb,
                      height: thumb,
                      decoration: BoxDecoration(
                        color: t.text,
                        borderRadius: UiV2Radii.brPill,
                        boxShadow: t.shadow1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 播放控制行（上一首 / 播放 / 下一首 + 可选随机、循环）
class UiV2Transport extends ConsumerWidget {
  /// 按钮尺寸（播放条 40，沉浸页 48）
  final double buttonSize;

  /// 是否大号播放键（沉浸页 64）
  final bool largePlay;

  /// 是否显示随机 / 循环（播放条宽屏与沉浸页显示）
  final bool showOptions;

  /// 参与均分宽度（沉浸页 space-between，播放条紧凑居中）
  final bool spread;

  /// 构造控制行
  const UiV2Transport({
    super.key,
    this.buttonSize = 40,
    this.largePlay = false,
    this.showOptions = true,
    this.spread = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(isPlayingProvider);
    final mode = ref.watch(playModeProvider);
    final shuffle = ref.watch(shuffleProvider);
    final hasTrack = ref.watch(currentTrackIdProvider) != null;
    final controller = ref.read(playbackControllerProvider);
    final notifier = ref.read(playModeProvider.notifier);

    final repeatIcon = (shuffle || mode == PlayMode.singleLoop)
        ? UiV2Icons.repeatOne
        : UiV2Icons.repeat;
    final repeatPressed = !shuffle && mode != PlayMode.sequential;
    final repeatLabel = shuffle
        ? '循环模式：随机播放中，点击回到列表循环'
        : '循环模式：${_modeLabel(mode)}';

    final buttons = <Widget>[
      if (showOptions)
        UiV2IconButton(
          icon: UiV2Icons.shuffle,
          semanticLabel: '随机播放',
          size: buttonSize,
          pressed: shuffle,
          disabled: !hasTrack,
          onTap: () async {
            await ref.read(shuffleProvider.notifier).toggle();
            showUiV2Toast(
              context,
              ref.watch(shuffleProvider) ? '随机播放已开启（循环项暂停生效）' : '已关闭随机 · 列表循环',
            );
          },
        ),
      UiV2IconButton(
        key: const ValueKey('transport_prev'),
        icon: UiV2Icons.prev,
        semanticLabel: '上一首',
        size: buttonSize,
        disabled: !hasTrack,
        onTap: hasTrack ? controller.previous : null,
      ),
      UiV2PlayButton(
        key: const ValueKey('transport_play'),
        playing: playing,
        large: largePlay,
        onTap: hasTrack ? controller.toggle : null,
      ),
      UiV2IconButton(
        key: const ValueKey('transport_next'),
        icon: UiV2Icons.next,
        semanticLabel: '下一首',
        size: buttonSize,
        disabled: !hasTrack,
        onTap: hasTrack ? controller.next : null,
      ),
      if (showOptions)
        UiV2IconButton(
          icon: repeatIcon,
          semanticLabel: repeatLabel,
          size: buttonSize,
          pressed: repeatPressed,
          inactive: shuffle,
          onTap: () async {
            if (shuffle) {
              await ref.read(shuffleProvider.notifier).set(false);
              await notifier.set(PlayMode.listLoop);
              if (context.mounted) showUiV2Toast(context, '已退出随机 · 列表循环');
              return;
            }
            await notifier.cycle();
            if (context.mounted) {
              showUiV2Toast(context, _modeLabel(ref.read(playModeProvider)));
            }
          },
        ),
    ];

    if (spread) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: buttons,
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: UiV2Spacing.s2),
          buttons[i],
        ],
      ],
    );
  }

  /// 播放模式中文名（原型 MODE_LABEL）
  static String _modeLabel(PlayMode mode) => switch (mode) {
        PlayMode.listLoop => '列表循环',
        PlayMode.singleLoop => '单曲循环',
        PlayMode.sequential => '顺序播放',
        PlayMode.shuffle => '随机播放',
      };
}

/// 播放条（.playerbar）
class UiV2PlayerBar extends ConsumerWidget {
  /// 布局档位（由 AppShell 计算）
  final bool wide;

  /// 是否处于平板口径（768–1180）
  final bool tablet;

  /// 构造播放条
  const UiV2PlayerBar({super.key, required this.wide, required this.tablet});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final position = ref.watch(positionProvider);
    final duration = ref.watch(durationProvider);
    final ratio = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: t.surface.withValues(alpha: 0.94),
            border: Border(top: BorderSide(color: t.line)),
          ),
          padding: EdgeInsets.fromLTRB(
            UiV2Spacing.s4,
            UiV2Spacing.s2,
            UiV2Spacing.s4,
            UiV2Spacing.s2 + bottomInset,
          ),
          child: Stack(
            children: [
              // 移动端顶部 2px 细线进度（.pb__progress-mini）
              if (!wide)
                Positioned(
                  left: -UiV2Spacing.s4,
                  right: -UiV2Spacing.s4,
                  top: -UiV2Spacing.s2,
                  child: SizedBox(
                    height: 2,
                    child: Stack(
                      children: [
                        Container(color: t.surface3),
                        FractionallySizedBox(
                          widthFactor: ratio,
                          child: Container(color: t.accent),
                        ),
                      ],
                    ),
                  ),
                ),
              SizedBox(
                // 宽屏三区内容高约 42(播放键) + 4 + 20 = 66 > 64，
                // 用 Expanded 让进度条吸收压缩，避免溢出警示条
                height: UiV2Metrics.playerBarHeight,
                child: wide
                    ? _wideLayout(context, ref, tablet)
                    : _compactLayout(ref),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- 移动端布局：信息 + 三个控制键 ----------------
  Widget _compactLayout(WidgetRef ref) {
    return Row(
      children: [
        const Expanded(child: _NowPlayingInfo(coverSize: 46, showMeta: true)),
        const SizedBox(width: UiV2Spacing.s2),
        UiV2IconButton(
          icon: UiV2Icons.prev,
          semanticLabel: '上一首',
          size: 38,
          onTap: ref.watch(currentTrackIdProvider) == null
              ? null
              : ref.read(playbackControllerProvider).previous,
        ),
        const SizedBox(width: UiV2Spacing.s1),
        UiV2PlayButton(
          playing: ref.watch(isPlayingProvider),
          onTap: ref.watch(currentTrackIdProvider) == null
              ? null
              : ref.read(playbackControllerProvider).toggle,
        ),
        const SizedBox(width: UiV2Spacing.s1),
        UiV2IconButton(
          icon: UiV2Icons.next,
          semanticLabel: '下一首',
          size: 38,
          onTap: ref.watch(currentTrackIdProvider) == null
              ? null
              : ref.read(playbackControllerProvider).next,
        ),
      ],
    );
  }

  // ---------------- 宽屏布局：三区一行 ----------------
  Widget _wideLayout(BuildContext context, WidgetRef ref, bool tablet) {
    final hasTrack = ref.watch(currentTrackIdProvider) != null;
    return Row(
      children: [
        // 第一区
        // 平板档也要显示歌名/歌手（之前为躲溢出直接不画，属于治标）
        Expanded(
          flex: 4,
          child: const _NowPlayingInfo(coverSize: 52, showMeta: true),
        ),
        const SizedBox(width: UiV2Spacing.s3),
        // 第二区：控件行 + 进度条
        Expanded(
          flex: 4,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // 爱心已在第一区（_NowPlayingInfo）里画过，中区只放传输控件
                  const Spacer(),
                  UiV2Transport(buttonSize: 36, showOptions: true),
                  const Spacer(),
                  // 队列/展开在第三区已经画了一遍；平板档这里再画一次会让
                  // 第二区（约 300px）塞不下 326px，实测溢出 26px 并出现黄黑条纹。
                ],
              ),
              const SizedBox(height: UiV2Spacing.s1),
              const Flexible(child: UiV2ProgressBar()),
            ],
          ),
        ),
        const SizedBox(width: UiV2Spacing.s3),
        // 第三区：音量 / 下载 / 队列 / 展开
        Expanded(
          flex: 3,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!tablet) ...[
                const _MuteButton(),
                const SizedBox(width: UiV2Spacing.s2),
                const UiV2VolumeSlider(),
                const SizedBox(width: UiV2Spacing.s2),
              ],
              UiV2IconButton(
                icon: UiV2Icons.download,
                semanticLabel: '下载任务',
                onTap: () => ref.read(navProvider.notifier).go('downloads'),
              ),
              UiV2IconButton(
                key: const ValueKey('player_queue'),
                icon: UiV2Icons.queue,
                semanticLabel: '播放队列',
                onTap: () => showQueueSheet(context),
              ),
              UiV2IconButton(
                key: const ValueKey('player_expand'),
                icon: UiV2Icons.expand,
                semanticLabel: '展开播放页',
                onTap: hasTrack
                    ? () => ref.read(nowPlayingProvider.notifier).open()
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 播放条左侧信息块（封面 + 歌名/艺人 + 爱心）
class _NowPlayingInfo extends ConsumerWidget {
  /// 封面边长（移动端 46，宽屏 52）
  final double coverSize;

  /// 是否显示歌名与艺人（平板口径只留封面）
  final bool showMeta;

  /// 构造信息块
  const _NowPlayingInfo({required this.coverSize, required this.showMeta});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);
    final meta = song == null ? null : ref.watch(catalogTracksProvider)[song.id];

    return Row(
      children: [
        UiV2Pressable(
          onTap: song == null
              ? null
              : () => ref.read(nowPlayingProvider.notifier).open(),
          pressedScale: 1,
          child: UiV2Cover(
            source: song == null
                ? null
                : resolveSongCover(ref, song, catalogCover: meta?.cover),
            size: coverSize,
            sourceId: song?.sourceId,
          ),
        ),
        if (showMeta) ...[
          const SizedBox(width: UiV2Spacing.s3),
          const Expanded(child: _NowPlayingText(style: null)),
          const _LikeButton(size: 40),
        ],
      ],
    );
  }
}

/// 播放条文本块（歌名 + 艺人 / 准备中提示）
class _NowPlayingText extends ConsumerWidget {
  /// 标题样式（null 用默认 trackTitle）
  final TextStyle? style;

  /// 构造文本块
  const _NowPlayingText({required this.style});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final song = ref.watch(currentSongProvider);
    final pending = ref.watch(pendingProvider) != null;
    final title = song == null
        ? '未在播放'
        : (pending ? '准备播放中…' : song.title);
    final subtitle = song == null ? '选择一首歌曲开始' : song.artist;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: (style ?? UiV2Text.trackTitle).copyWith(color: t.text),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          subtitle,
          style: UiV2Text.trackArtist.copyWith(color: t.textDim),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// 播放条/沉浸页的爱心按钮（无曲目时禁用）
class _LikeButton extends ConsumerWidget {
  final double size;

  const _LikeButton({required this.size});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final song = ref.watch(currentSongProvider);
    final liked = ref.watch(likedProvider);
    final isLiked =
        song != null && liked.any((r) => r.songKey == song.globalKey);
    return UiV2IconButton(
      icon: isLiked ? UiV2Icons.heartFill : UiV2Icons.heart,
      semanticLabel: isLiked ? '取消喜欢' : '喜欢',
      size: size,
      color: isLiked ? t.accent : t.textDim,
      disabled: song == null,
      onTap: song == null
          ? null
          : () async {
              await ref.read(likedProvider.notifier).toggle(song);
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

/// 静音键（.pb__tools 里散装的 #pb-mute）
class _MuteButton extends ConsumerWidget {
  /// 构造静音键
  const _MuteButton();

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