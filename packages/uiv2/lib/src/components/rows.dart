/// 曲目行与卡片 —— 数据一律是 core 的真实模型（[Song] / [Album] / [Artist] /
/// [Playlist]），配表（CatalogTrack）只作为**可选的展示元数据**参与渲染。
///
/// 这样页面不再假设「曲目一定在配表里」：本地扫描曲目、规则源结果、插件源结果
/// 与演示曲库曲目共用同一套组件。
library;

import 'package:core/core.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalog.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../providers/providers.dart';
import 'surfaces.dart';

/// 秒 → m:ss（曲目行、播放条、下载页共用）
String formatSeconds(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final m = s ~/ 60;
  final r = s % 60;
  return '$m:${r < 10 ? '0' : ''}$r';
}

/// 均衡器三柱（.eq）
class UiV2Eq extends StatefulWidget {
  /// 柱体颜色
  final Color color;

  /// 是否播放动画
  final bool animated;

  /// 构造均衡器
  const UiV2Eq({super.key, required this.color, this.animated = true});

  @override
  State<UiV2Eq> createState() => _UiV2EqState();
}

class _UiV2EqState extends State<UiV2Eq> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animated) _c.repeat();
  }

  @override
  void didUpdateWidget(UiV2Eq oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.animated && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              _bar(i),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bar(int index) {
    final phase = (_c.value + index * 0.2) % 1.0;
    final t = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    final height = widget.animated ? 4 + t * 9 : 5.0;
    return Container(
      width: 3,
      height: height,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

/// 转圈（.spin，720ms 线性）
class UiV2Spinner extends StatefulWidget {
  /// 圆环直径
  final double size;

  /// 底环颜色
  final Color trackColor;

  /// 高亮弧颜色
  final Color color;

  /// 构造转圈
  const UiV2Spinner({
    super.key,
    required this.trackColor,
    required this.color,
    this.size = 14,
  });

  @override
  State<UiV2Spinner> createState() => _UiV2SpinnerState();
}

class _UiV2SpinnerState extends State<UiV2Spinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RotationTransition(
        turns: _c,
        child: CustomPaint(
          painter: _RingPainter(track: widget.trackColor, head: widget.color),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  /// 底环颜色
  final Color track;

  /// 高亮弧颜色
  final Color head;

  /// 构造画笔
  const _RingPainter({required this.track, required this.head});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(1, 1, size.width - 2, size.height - 2);
    canvas.drawArc(
      rect,
      0,
      6.28318,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = track,
    );
    canvas.drawArc(
      rect,
      -1.5708,
      1.9,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = head,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.track != track || oldDelegate.head != head;
}

/// 封面缩略图（.track__cover / .pb__cover / .pick__cover / .dl__cover 共用外观）
class UiV2Cover extends ConsumerWidget {
  /// 封面地址：http(s) 网络图 / assets 资产 / 空表示占位
  final String? source;

  /// 边长（[double.infinity] 表示撑满父级正方形）
  final double size;

  /// 圆角
  final double radius;

  /// 状态蒙层
  final Widget? overlay;

  /// 曲目来源 id：给了它就会自动带上该源的图片请求头（如 referer）
  final String? sourceId;

  /// 构造封面
  const UiV2Cover({
    super.key,
    required this.source,
    required this.size,
    this.radius = 8,
    this.overlay,
    this.sourceId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final content = (source == null || source!.isEmpty)
        ? Container(
            color: t.surface3,
            alignment: Alignment.center,
            child: UiV2Icon(UiV2Icons.note, size: 22, color: t.textMute),
          )
        : _image(context, ref);

    final stacked = Stack(
      fit: StackFit.expand,
      children: [
        content,
        if (overlay != null) overlay!,
      ],
    );

    if (size == double.infinity) {
      return ClipRRect(borderRadius: BorderRadius.circular(radius), child: stacked);
    }
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: stacked),
    );
  }

  /// 该源的图片请求头（没有就空）
  Map<String, String> _headersFor(WidgetRef ref) {
    final id = sourceId;
    if (id == null || id.isEmpty) return const <String, String>{};
    final source = ref.watch(sourceManagerProvider).getSource(id);
    // Dart 没有交集类型：对不相关接口的 is 判断不做类型提升，这里显式转一次
    if (source is! ImageHeaderSource) return const <String, String>{};
    return (source as ImageHeaderSource).imageHeaders;
  }

  Widget _image(BuildContext context, WidgetRef ref) {
    final src = source!;
    final t = UiV2Theme.of(context);
    Widget fallback() => Container(
          color: t.surface3,
          alignment: Alignment.center,
          child: UiV2Icon(UiV2Icons.note, size: 22, color: t.textMute),
        );
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return Image.network(
        src,
        // 枫叶等源校验 referer，不带头会 403（封面显示占位）
        headers: _headersFor(ref),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback(),
      );
    }
    if (src.startsWith('assets/')) {
      return Image.asset(
        src,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback(),
      );
    }
    // 其它（本地文件路径等）本包不做文件解码，交给占位
    return fallback();
  }
}

/// 曲目行（.track）—— 三段式：曲目信息 / 时长 / 操作
class UiV2SongRow extends ConsumerWidget {
  /// 曲目（core 模型）
  final Song song;

  /// 展示元数据（配表曲目，可为空）
  final CatalogTrack? meta;

  /// 行号（从 0 起）
  final int index;

  /// 是否显示封面
  final bool showArt;

  /// 副行是否显示专辑名
  final bool showAlbum;

  /// 是否显示来源标签
  final bool showSource;

  /// 搜索命中高亮词
  final String? highlight;

  /// 覆盖副行文案
  final String? subtitleOverride;

  /// 覆盖时长（秒）
  final int? durationOverride;

  /// 覆盖来源名
  final String? sourceNameOverride;

  /// 点击行（播放）
  final VoidCallback onTap;

  /// 点击爱心
  final VoidCallback onToggleLike;

  /// 点击更多
  final VoidCallback onMore;

  /// 构造曲目行
  const UiV2SongRow({
    super.key,
    required this.song,
    required this.index,
    required this.onTap,
    required this.onToggleLike,
    required this.onMore,
    this.meta,
    this.showArt = false,
    this.showAlbum = true,
    this.showSource = true,
    this.highlight,
    this.subtitleOverride,
    this.durationOverride,
    this.sourceNameOverride,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final currentKey = ref.watch(currentTrackIdProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final pendingKey = ref.watch(pendingProvider);
    final liked = ref.watch(likedProvider);

    final globalKey = song.globalKey;
    final isCurrent = currentKey == globalKey || currentKey == song.id;
    final isPending = isCurrent && pendingKey == globalKey;
    final isPlay = isCurrent && isPlaying && !isPending;
    final isLiked = liked.any((r) => r.songKey == globalKey);
    final cover = meta?.cover ?? song.coverUrl;
    final duration = durationOverride ?? song.duration ?? meta?.duration ?? 0;
    final downloaded = song.localPath != null && song.localPath!.isNotEmpty;
    final subtitle = subtitleOverride ??
        (showAlbum
            ? [song.artist, song.album ?? ''].where((s) => s.isNotEmpty).join(' · ')
            : song.artist);

    final overlay = (isPlay || isPending)
        ? Container(
            color: const Color(0x8C060709),
            alignment: Alignment.center,
            child: isPending
                ? UiV2Spinner(
                    trackColor: const Color(0x57FFFFFF),
                    color: const Color(0xFFFFFFFF),
                  )
                : UiV2Eq(color: const Color(0xFFFFFFFF)),
          )
        : null;

    return UiV2Pressable(
      onTap: onTap,
      pressedScale: 1,
      radius: UiV2Radii.brMd,
      hoverColor: t.surface2,
      child: AnimatedContainer(
        duration: UiV2Motion.d1,
        curve: UiV2Motion.enter,
        padding: const EdgeInsets.symmetric(
          horizontal: UiV2Spacing.s3,
          vertical: UiV2Spacing.s2,
        ),
        decoration: BoxDecoration(
          color: isCurrent ? t.accentSoft : const Color(0x00000000),
          borderRadius: UiV2Radii.brMd,
        ),
        child: Row(
          children: [
            if (showArt)
              UiV2Cover(
                source: cover,
                size: 42,
                overlay: overlay,
                sourceId: song.sourceId,
              )
            else
              SizedBox(
                width: 28,
                child: Center(
                  child: isPlay
                      ? UiV2Eq(color: t.accent)
                      : Text(
                          '${index + 1}',
                          style: UiV2Text.duration.copyWith(
                            color: isCurrent ? t.accent : t.textMute,
                          ),
                        ),
                ),
              ),
            const SizedBox(width: UiV2Spacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _title(t, isCurrent),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          subtitle,
                          style: UiV2Text.trackArtist.copyWith(color: t.textDim),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (downloaded) ...[
                        const SizedBox(width: 6),
                        const UiV2Badge(label: '已下载', icon: UiV2Icons.check),
                      ],
                      if (showSource) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: t.surface3,
                              borderRadius: UiV2Radii.brPill,
                            ),
                            child: Text(
                              sourceNameOverride ?? _sourceLabel(ref),
                              style: UiV2Text.hint.copyWith(color: t.textDim),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: UiV2Spacing.s2),
            Text(
              formatSeconds(duration),
              style: UiV2Text.duration.copyWith(color: t.textMute),
            ),
            const SizedBox(width: UiV2Spacing.s2),
            UiV2IconButton(
              icon: isLiked ? UiV2Icons.heartFill : UiV2Icons.heart,
              size: 36,
              color: isLiked ? t.accent : t.textMute,
              semanticLabel: isLiked ? '取消喜欢' : '喜欢',
              onTap: onToggleLike,
            ),
            UiV2IconButton(
              icon: UiV2Icons.more,
              size: 36,
              semanticLabel: '更多操作：${song.title}',
              onTap: onMore,
            ),
          ],
        ),
      ),
    );
  }

  Widget _title(UiV2Tokens t, bool isCurrent) {
    final style = UiV2Text.trackTitle.copyWith(
      color: isCurrent ? t.accent : t.text,
    );
    final text = song.title.isEmpty ? '（未知曲目）' : song.title;
    final q = highlight;
    final query = (q == null || q.isEmpty) ? null : q.toLowerCase();
    final at = query == null ? -1 : text.toLowerCase().indexOf(query);
    if (query == null || at < 0 || at + query.length > text.length) {
      return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, at)),
          TextSpan(
            text: text.substring(at, at + query.length),
            style: style.copyWith(backgroundColor: t.accentSoft2),
          ),
          TextSpan(text: text.substring(at + query.length)),
        ],
      ),
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 来源展示名：注册源的真实名字优先
  String _sourceLabel(WidgetRef ref) {
    final sources = ref.watch(sourceListProvider).value ?? const <MusicSource>[];
    for (final s in sources) {
      if (s.sourceInfo.id == song.sourceId) return s.sourceInfo.name;
    }
    return kSourceDisplayNames[song.sourceId] ?? song.sourceId;
  }
}

/// 图标按钮（.icon-btn）
class UiV2IconButton extends StatelessWidget {
  /// 图标名
  final String icon;

  /// 无障碍标签
  final String semanticLabel;

  /// 点击回调
  final VoidCallback? onTap;

  /// 尺寸
  final double size;

  /// 图标尺寸
  final double iconSize;

  /// 颜色
  final Color? color;

  /// 是否按下态
  final bool pressed;

  /// 是否禁用
  final bool disabled;

  /// 是否半透明
  final bool inactive;

  /// 圆角：默认胶囊（方形尺寸下等于圆形）
  ///
  /// 需要与外部描边框对齐时传方圆角（如 UiV2Radii.brMd），
  /// 否则 hover / 按下底色会是圆形，和方框描边打架。
  final BorderRadius radius;

  /// 构造图标按钮
  const UiV2IconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onTap,
    this.size = 40,
    this.iconSize = 22,
    this.color,
    this.pressed = false,
    this.disabled = false,
    this.inactive = false,
    this.radius = UiV2Radii.brPill,
  });

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final fg = color ?? (pressed ? t.accent : t.textDim);
    return Opacity(
      opacity: disabled ? 0.4 : (inactive ? 0.45 : 1),
      child: Semantics(
        label: semanticLabel,
        button: true,
        enabled: !disabled,
        child: UiV2Pressable(
          onTap: disabled ? null : onTap,
          enabled: !disabled,
          radius: radius,
          hoverColor: t.surface2,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: pressed ? t.accentSoft : const Color(0x00000000),
              borderRadius: radius,
            ),
            alignment: Alignment.center,
            child: UiV2Icon(icon, size: iconSize, color: fg),
          ),
        ),
      ),
    );
  }
}

/// 播放按钮（.play-btn / .play-btn--lg）
class UiV2PlayButton extends StatelessWidget {
  /// 是否正在播放
  final bool playing;

  /// 点击回调
  final VoidCallback? onTap;

  /// 是否大号
  final bool large;

  /// 构造播放按钮
  const UiV2PlayButton({
    super.key,
    required this.playing,
    this.onTap,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final size = large ? 64.0 : 42.0;
    final iconSize = large ? 30.0 : 22.0;
    return Semantics(
      label: playing ? '暂停' : '播放',
      button: true,
      child: UiV2Pressable(
        onTap: onTap,
        pressedScale: 0.95,
        enabled: onTap != null,
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: t.accent,
              borderRadius: UiV2Radii.brPill,
            ),
            alignment: Alignment.center,
            child: UiV2Icon(
              playing ? UiV2Icons.pause : UiV2Icons.play,
              size: iconSize,
              color: t.accentInk,
            ),
          ),
        ),
      ),
    );
  }
}

/// 四格拼贴封面（.pl-mosaic）
class UiV2Mosaic extends StatelessWidget {
  /// 四个封面地址
  final List<String> covers;

  /// 补位色
  final Color fallback;

  /// 圆角
  final double radius;

  /// 构造拼贴
  const UiV2Mosaic({
    super.key,
    required this.covers,
    required this.fallback,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final slots = List<String>.generate(
      4,
      (i) => i < covers.length && covers[i].isNotEmpty ? covers[i] : '',
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Column(
        children: [
          for (var row = 0; row < 2; row++)
            Expanded(
              child: Row(
                children: [
                  for (var col = 0; col < 2; col++)
                    Expanded(child: _cell(slots[row * 2 + col])),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(String src) {
    if (src.isEmpty) return Container(color: fallback);
    if (src.startsWith('http')) return Image.network(src, fit: BoxFit.cover);
    if (src.startsWith('assets/')) return Image.asset(src, fit: BoxFit.cover);
    return Container(color: fallback);
  }
}

/// 卡片外壳（.card）
class UiV2CardShell extends StatefulWidget {
  /// 固定宽度
  final double? width;

  /// 封面区
  final Widget art;

  /// 标题
  final String title;

  /// 说明行
  final List<String> meta;

  /// 点击卡片
  final VoidCallback onTap;

  /// 构造卡片外壳
  const UiV2CardShell({
    super.key,
    required this.art,
    required this.title,
    required this.meta,
    required this.onTap,
    this.width,
  });

  @override
  State<UiV2CardShell> createState() => _UiV2CardShellState();
}

class _UiV2CardShellState extends State<UiV2CardShell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final body = AnimatedContainer(
      duration: UiV2Motion.d2,
      curve: UiV2Motion.enter,
      transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(aspectRatio: 1, child: widget.art),
          const SizedBox(height: UiV2Spacing.s3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  style: UiV2Text.cardName.copyWith(color: t.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                for (final line in widget.meta)
                  if (line.isNotEmpty)
                    Text(
                      line,
                      style: UiV2Text.hint.copyWith(color: t.textDim),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
              ],
            ),
          ),
        ],
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.width == null ? body : SizedBox(width: widget.width, child: body),
      ),
    );
  }
}

/// 卡片封面区（.card__art）
class UiV2CardArt extends StatefulWidget {
  /// 封面内容
  final Widget child;

  /// 点击封面
  final VoidCallback onTap;

  /// 点击播放浮标
  final VoidCallback onPlay;

  /// 播放浮标标签
  final String playLabel;

  /// 封面标签
  final String semanticLabel;

  /// 左上角徽标
  final Widget? badge;

  /// 构造封面区
  const UiV2CardArt({
    super.key,
    required this.child,
    required this.onTap,
    required this.onPlay,
    required this.playLabel,
    required this.semanticLabel,
    this.badge,
  });

  @override
  State<UiV2CardArt> createState() => _UiV2CardArtState();
}

class _UiV2CardArtState extends State<UiV2CardArt> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final alwaysShow = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final show = alwaysShow || _hover;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: UiV2Radii.brMd, boxShadow: t.shadow1),
          child: ClipRRect(
            borderRadius: UiV2Radii.brMd,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: t.surface2, child: widget.child),
                if (widget.badge != null) Positioned(left: 8, top: 8, child: widget.badge!),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: IgnorePointer(
                    ignoring: !alwaysShow,
                    child: AnimatedOpacity(
                      duration: UiV2Motion.d2,
                      curve: UiV2Motion.enter,
                      opacity: show ? 1 : 0,
                      child: AnimatedSlide(
                        duration: UiV2Motion.d2,
                        curve: UiV2Motion.enter,
                        offset: show ? Offset.zero : const Offset(0, 0.15),
                        child: Semantics(
                          label: widget.playLabel,
                          button: true,
                          child: UiV2Pressable(
                            onTap: widget.onPlay,
                            pressedScale: 0.95,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: t.accent,
                                borderRadius: UiV2Radii.brPill,
                                boxShadow: t.shadow2,
                              ),
                              alignment: Alignment.center,
                              child: UiV2Icon(UiV2Icons.play, size: 22, color: t.accentInk),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 专辑卡片（core [Album]）
class UiV2AlbumCard extends StatelessWidget {
  /// 专辑
  final Album album;

  /// 卡片宽度
  final double width;

  /// 点击卡片
  final VoidCallback onTap;

  /// 点击播放
  final VoidCallback onPlay;

  /// 曲目数
  final int? trackCount;

  /// 构造专辑卡
  const UiV2AlbumCard({
    super.key,
    required this.album,
    required this.onTap,
    required this.onPlay,
    this.width = 172,
    this.trackCount,
  });

  @override
  Widget build(BuildContext context) {
    final count = trackCount ?? album.songCount ?? album.songs.length;
    final year = album.extra['year'];
    final genre = album.extra['genre'];
    return UiV2CardShell(
      width: width,
      art: UiV2CardArt(
        child: UiV2Cover(source: album.coverUrl, size: double.infinity),
        onTap: onTap,
        onPlay: onPlay,
        playLabel: '播放专辑：${album.title}',
        semanticLabel: '${album.title}，${album.artist}',
      ),
      title: album.title,
      meta: [
        [album.artist, if (year != null) '$year'].where((s) => s.isNotEmpty).join(' · '),
        [if (count > 0) '$count 首', if (genre != null) '$genre']
            .where((s) => s.isNotEmpty)
            .join(' · '),
      ],
      onTap: onTap,
    );
  }
}

/// 艺人卡片（core [Artist]）
class UiV2ArtistCard extends StatelessWidget {
  /// 艺人
  final Artist artist;

  /// 卡片宽度
  final double width;

  /// 点击卡片
  final VoidCallback onTap;

  /// 点击播放
  final VoidCallback onPlay;

  /// 说明行
  final List<String> meta;

  /// 构造艺人卡
  const UiV2ArtistCard({
    super.key,
    required this.artist,
    required this.onTap,
    required this.onPlay,
    this.width = 172,
    this.meta = const [],
  });

  @override
  Widget build(BuildContext context) {
    return UiV2CardShell(
      width: width,
      art: UiV2CardArt(
        child: UiV2Cover(source: artist.avatar, size: double.infinity),
        onTap: onTap,
        onPlay: onPlay,
        playLabel: '播放艺人：${artist.name}',
        semanticLabel: artist.name,
      ),
      title: artist.name,
      meta: meta.isEmpty ? [artist.description ?? ''] : meta,
      onTap: onTap,
    );
  }
}

/// 歌单卡片（core [Playlist] + 拼贴封面）
class UiV2PlaylistCard extends StatelessWidget {
  /// 歌单
  final Playlist playlist;

  /// 拼贴封面
  final List<String> covers;

  /// 补位色
  final Color fallback;

  /// 副标题
  final String subtitle;

  /// 卡片宽度
  final double width;

  /// 是否自建歌单
  final bool owned;

  /// 点击卡片
  final VoidCallback onTap;

  /// 点击播放
  final VoidCallback onPlay;

  /// 构造歌单卡
  const UiV2PlaylistCard({
    super.key,
    required this.playlist,
    required this.onTap,
    required this.onPlay,
    this.covers = const [],
    this.fallback = const Color(0xFF3B4C9E),
    this.subtitle = '',
    this.width = 172,
    this.owned = false,
  });

  @override
  Widget build(BuildContext context) {
    return UiV2CardShell(
      width: width,
      art: UiV2CardArt(
        child: UiV2Mosaic(covers: covers, fallback: fallback),
        onTap: onTap,
        onPlay: onPlay,
        playLabel: '播放歌单：${playlist.name}',
        semanticLabel: playlist.name,
        badge: owned ? const UiV2Badge(label: '我的', tone: UiV2BadgeTone.glass) : null,
      ),
      title: playlist.name,
      meta: [if (subtitle.isNotEmpty) subtitle],
      onTap: onTap,
    );
  }
}

/// 曲目列表容器（.tracks：gap 2）
class UiV2TrackList extends StatelessWidget {
  /// 行组件
  final List<Widget> rows;

  /// 构造列表
  const UiV2TrackList({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          rows[i],
        ],
      ],
    );
  }
}

/// 卡片网格（.grid-cards）
class UiV2CardGrid extends StatelessWidget {
  /// 卡片
  final List<Widget> children;

  /// 文字块高度（封面为正方形，格子高度 = 列宽 + 该值）
  final double textBlockHeight;

  /// 构造网格
  const UiV2CardGrid({
    super.key,
    required this.children,
    this.textBlockHeight = 78,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const minWidth = 148.0;
        const gap = UiV2Spacing.s4;
        final columns =
            ((constraints.maxWidth + gap) / (minWidth + gap)).floor().clamp(2, 8);
        final cellWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: columns,
          mainAxisSpacing: gap,
          crossAxisSpacing: gap,
          childAspectRatio: cellWidth / (cellWidth + textBlockHeight),
          children: children,
        );
      },
    );
  }
}

/// 横向滚动轨道（.rail + .od-rail）
class UiV2Rail extends StatelessWidget {
  /// 子项
  final List<Widget> children;

  /// 间距
  final double gap;

  /// 构造轨道
  const UiV2Rail({super.key, required this.children, this.gap = UiV2Spacing.s4});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            children[i],
          ],
        ],
      ),
    );
  }
}
