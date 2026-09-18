/// 歌单/专辑详情头部公共组件（StatefulWidget）
///
/// 供本地歌单（PlaylistDetailPage）、远程歌单（DiscoverPlaylistPage）与
/// 专辑页（AlbumPage）复用，保证三端头部视觉一致。
/// 组件需真实挂载进 widget 树（State 生命周期驱动封面主色提取）。
///
/// 视觉参考 PixelPlayer CollapsingAlbumTopBar：
/// - 大封面图铺满头部（BoxFit.cover）+ 底部垂直渐变遮罩过渡到表面色
/// - 顶部状态栏遮罩；标题/副标题左对齐靠底部；大号「播放全部」按钮
/// - 无封面时回落封面主色渐变 + 自适应前景色
///
/// - [PlaylistHeaderMode.flexible]：竖屏 SliverAppBar 折叠头（flexibleSpace 内容）
/// - [PlaylistHeaderMode.wide]：宽屏左侧完整面板（含顶部返回条）
///
/// 封面主色提取：封面加载完成后用 [CoverPalette.extract] 异步提取，
/// 通过 [onColorExtracted] 回传，供页面同步 SliverAppBar 折叠态配色。
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。
library;

import 'package:flutter/material.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radius.dart';
import 'cover_palette.dart';
import 'cover_image.dart';

/// 头部模式
enum PlaylistHeaderMode {
  /// 手机/竖屏 SliverAppBar 折叠头（flexibleSpace 内容）
  flexible,

  /// 宽屏左列完整面板（含顶部返回条）
  wide,
}

/// 歌单/专辑详情头部（内部负责封面主色提取与主题色渲染）
class PlaylistHeaderView extends StatefulWidget {
  /// 名称（歌单名/专辑名）
  final String name;

  /// 封面 URL（null 或无 cover 来源时回落主色渐变）
  final String? coverUrl;

  /// 描述文案（如「N 首歌曲」/ 歌手 · N 首 / 错误信息）
  final String? subtitle;

  /// 是否「我最喜欢」虚拟歌单（心形封面）
  final bool isFavorite;

  /// 「播放全部」回调（null 时按钮禁用态）
  final VoidCallback? onPlayAll;

  /// 封面主色提取完成回调（参数为主题色，null 表示无封面/失败）
  final ValueChanged<Color?>? onColorExtracted;

  /// 头部模式（flexible / wide）
  final PlaylistHeaderMode mode;

  /// 返回回调（仅 wide 模式生效）
  final VoidCallback? onBack;

  const PlaylistHeaderView({
    super.key,
    required this.name,
    this.coverUrl,
    this.subtitle,
    this.isFavorite = false,
    this.onPlayAll,
    this.onColorExtracted,
    required this.mode,
    this.onBack,
  });

  @override
  State<PlaylistHeaderView> createState() => _PlaylistHeaderViewState();
}

class _PlaylistHeaderViewState extends State<PlaylistHeaderView> {
  /// 封面主色（未提取到为 null → 用主题默认色）
  Color? _dominant;
  ImageStream? _stream;

  late final ImageStreamListener _listener = ImageStreamListener(
    (info, _) {
      CoverPalette.extract(info.image).then((color) {
        if (!mounted) return;
        setState(() => _dominant = color);
        _notifyColor(color);
      });
    },
    onError: (Object _, StackTrace? _) {
      if (!mounted) return;
      setState(() => _dominant = null);
      _notifyColor(null);
    },
  );

  /// 封面 ImageProvider（favorite/无封面返回 null）
  ImageProvider? get _provider {
    if (widget.isFavorite) return null;
    final url = widget.coverUrl;
    if (url == null || url.isEmpty) return null;
    return NetworkImage(url);
  }

  @override
  void initState() {
    super.initState();
    _loadPalette();
  }

  @override
  void didUpdateWidget(covariant PlaylistHeaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverUrl != widget.coverUrl) _loadPalette();
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  void _loadPalette() {
    _stream?.removeListener(_listener);
    _dominant = null;
    final provider = _provider;
    if (provider == null) {
      _notifyColor(null);
      return;
    }
    final stream = provider.resolve(ImageConfiguration.empty);
    _stream = stream;
    stream.addListener(_listener);
  }

  /// 帧后派发主色回调
  ///
  /// 回调由页面用于 setState 同步折叠态配色；若在 initState/build 期间同步
  /// 调用会触发 "setState() called during build" 红屏，故统一 post-frame 派发。
  void _notifyColor(Color? color) {
    final cb = widget.onColorExtracted;
    if (cb == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      cb(color);
    });
  }

  /// 背景主色：封面主题色或主题默认色
  ///
  /// 无封面时回落**主题主色系**（primaryContainer 派生），避免出现
  /// 一片灰面板与右侧列表形成生硬分隔（对齐 PixelPlayer 的主题色氛围）。
  Color get _bg {
    if (_dominant != null) return _dominant!;
    final cs = Theme.of(context).colorScheme;
    return Color.lerp(cs.primaryContainer, cs.surface, 0.35)!;
  }

  /// 无封面场景的前景色：按主色亮度自动黑/白
  Color get _fg => CoverPalette.foreground(_bg);

  /// 是否有可用封面大图背景
  bool get _hasArtwork {
    if (widget.isFavorite) return false;
    final url = widget.coverUrl;
    return url != null && url.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.mode) {
      PlaylistHeaderMode.flexible => _buildFlexibleSpace(context),
      PlaylistHeaderMode.wide => _buildWidePanel(context),
    };
  }

  // ==================== 背景层（封面大图 / 主色渐变 + 遮罩） ====================

  /// 背景：封面大图或主色渐变。
  ///
  /// [blendToSurface] 为 true 时（flexible：下方紧接列表）底部渐隐到表面色，
  /// 使封面自然过渡进列表；为 false 时（wide：独立左面板）保持整片主题色，
  /// 避免面板内部出现"上白下紫"的接缝。有封面图时叠加暗色 scrim 保证文字可读。
  Widget _buildBackground(BuildContext context,
      {required bool withTopScrim, required bool blendToSurface}) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. 底图
        if (_hasArtwork)
          CoverImage(
            url: widget.coverUrl,
            fit: BoxFit.cover,
            radius: 0,
          )
        else
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_bg, CoverPalette.darken(_bg, 0.3)],
              ),
            ),
          ),
        // 2. 遮罩：
        //    - flexible（下方接列表）：底部渐隐到表面色，封面自然过渡进列表
        //    - wide（独立左面板）：仅叠一层轻 scrim，保持整片主题色、无接缝
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: blendToSurface
                    ? const [0.0, 0.45, 0.75, 1.0]
                    : const [0.0, 1.0],
                colors: blendToSurface
                    ? [
                        Colors.transparent,
                        cs.surface.withValues(alpha: 0.30),
                        cs.surface.withValues(alpha: 0.90),
                        cs.surface,
                      ]
                    : [
                        Colors.black.withValues(alpha: _hasArtwork ? 0.18 : 0.0),
                        Colors.black.withValues(alpha: _hasArtwork ? 0.30 : 0.0),
                      ],
              ),
            ),
          ),
        ),
        // 3. 顶部状态栏遮罩（保证返回按钮/状态栏可读）
        if (withTopScrim)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 96,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    cs.surface.withValues(alpha: 0.55),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 标题/副标题文字色：有封面遮罩时用表面色体系；纯主色背景用自适应前景
  Color get _titleColor =>
      _hasArtwork ? Theme.of(context).colorScheme.onSurface : _fg;

  Color get _subtitleColor => _hasArtwork
      ? Theme.of(context).colorScheme.onSurfaceVariant
      : _fg.withValues(alpha: 0.75);

  // ==================== 手机/竖屏：SliverAppBar 折叠头 ====================

  Widget _buildFlexibleSpace(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildBackground(context, withTopScrim: false, blendToSurface: true),
        // 内容：标题区靠底部（对齐 PixelPlayer 头部文字位置）
        SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s16, AppSpacing.s16, AppSpacing.s16, AppSpacing.s24),
                child: Column(
                  // 内容靠底部：标题区贴近列表，符合折叠头视觉预期
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.isFavorite) ...[
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          borderRadius:
                              BorderRadius.circular(AppRadius.s16),
                        ),
                        child: Icon(
                          Icons.favorite_rounded,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                          size: 26,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s8),
                    ],
                    Text(
                      widget.name,
                      style: tt.headlineSmall?.copyWith(
                        color: _titleColor,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        widget.subtitle!,
                        style: tt.bodyMedium?.copyWith(color: _subtitleColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.s16),
                    // 播放全部（大号按钮，对齐 PixelPlayer 播放按钮观感）
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s20,
                            vertical: AppSpacing.s12),
                        textStyle: tt.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      icon:
                          const Icon(Icons.play_arrow_rounded, size: 26),
                      label: const Text('播放全部'),
                      onPressed: widget.onPlayAll,
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

  // ==================== 宽屏：左侧完整面板 ====================

  Widget _buildWidePanel(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildBackground(context, withTopScrim: true, blendToSurface: false),
        SafeArea(
          child: Column(
            children: [
              // 顶部返回条（仅左列）
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s12, vertical: AppSpacing.s4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: widget.onBack,
                      tooltip: '返回',
                      style: IconButton.styleFrom(
                        backgroundColor: cs.surfaceContainerLow,
                        foregroundColor: cs.onSurface,
                      ),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    Expanded(
                      child: Text(
                        widget.name,
                        style: tt.titleMedium?.copyWith(
                          color: _titleColor,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // 底部标题区 + 播放全部
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        style: tt.headlineSmall?.copyWith(
                          color: _titleColor,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: AppSpacing.s4),
                        Text(
                          widget.subtitle!,
                          style:
                              tt.bodyMedium?.copyWith(color: _subtitleColor),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.s16),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s20,
                              vertical: AppSpacing.s12),
                          textStyle: tt.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 26),
                        label: const Text('播放全部'),
                        onPressed: widget.onPlayAll,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
