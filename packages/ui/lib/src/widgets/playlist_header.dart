/// 歌单详情头部公共组件（StatefulWidget）
///
/// 供本地歌单（PlaylistDetailPage）与远程歌单（DiscoverPlaylistPage）
/// 复用，保证两端头部视觉一致。组件需真实挂载进 widget 树
/// （State 生命周期驱动封面主色提取）：
/// - [PlaylistHeaderMode.flexible]：竖屏 SliverAppBar 折叠头——
///   背景用封面主题色渐变，内容宽度约束（maxWidth 560 居中），
///   row[封面(96), col(名称,描述,播放全部)]，折叠后仅 AppBar 标题保留。
/// - [PlaylistHeaderMode.wide]：宽屏左侧完整面板——
///   顶部返回条（AppBar 只占左列）+ 封面按面板宽度充满 + 名称/描述 + 播放全部。
///
/// 封面主色提取：封面加载完成后用 [CoverPalette.extract] 异步提取，
/// 通过 [onColorExtracted] 回传，供页面同步 SliverAppBar 折叠态配色。
/// 无封面/favorite/加载失败时回落主题默认色。
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。
library;

import 'package:flutter/material.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radius.dart';
import 'cover_palette.dart';

/// 头部模式
enum PlaylistHeaderMode {
  /// 手机/竖屏 SliverAppBar 折叠头（flexibleSpace 内容）
  flexible,

  /// 宽屏左列完整面板（含顶部返回条）
  wide,
}

/// 歌单详情头部（内部负责封面主色提取与主题色渲染）
class PlaylistHeaderView extends StatefulWidget {
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
        widget.onColorExtracted?.call(color);
      });
    },
    onError: (Object _, StackTrace? _) {
      if (!mounted) return;
      setState(() => _dominant = null);
      widget.onColorExtracted?.call(null);
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
      widget.onColorExtracted?.call(null);
      return;
    }
    final stream = provider.resolve(ImageConfiguration.empty);
    _stream = stream;
    stream.addListener(_listener);
  }

  /// 背景主色：封面主题色或主题默认色
  Color get _bg =>
      _dominant ?? Theme.of(context).colorScheme.surfaceContainerLow;

  /// 前景色：按背景亮度自动黑/白
  Color get _fg => CoverPalette.foreground(_bg);

  @override
  Widget build(BuildContext context) {
    return switch (widget.mode) {
      PlaylistHeaderMode.flexible => _buildFlexibleSpace(context),
      PlaylistHeaderMode.wide => _buildWidePanel(context),
    };
  }

  // ==================== 手机/竖屏：SliverAppBar 折叠头 ====================

  /// 完整 flexibleSpace 内容（含主题色渐变背景 + 宽度约束）
  ///
  /// 折叠后 SliverAppBar 标题由页面承担（背景色/前景色经
  /// [onColorExtracted] 同步）。
  Widget _buildFlexibleSpace(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final bg = _bg;
    final fg = _fg;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bg, CoverPalette.darken(bg, 0.28)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            // 头部内容宽度适宜：平板竖屏不撑满
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s16),
              child: Row(
                children: [
                  _cover(context, size: 96),
                  const SizedBox(width: AppSpacing.s16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.name,
                            style: tt.titleLarge?.copyWith(color: fg),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: AppSpacing.s4),
                          Text(widget.subtitle!,
                              style: tt.bodySmall
                                  ?.copyWith(color: fg.withValues(alpha: 0.75)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                        const SizedBox(height: AppSpacing.s8),
                        FilledButton.icon(
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('播放全部'),
                          onPressed: widget.onPlayAll,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==================== 宽屏：左侧完整面板 ====================

  /// 宽屏左侧面板：顶部返回条 + 封面充满 + 名称/描述 + 播放全部
  ///
  /// 背景为封面主题色渐变（上浅下深），整个面板形成独立视觉区块，
  /// 顶部返回条只占左列（右侧列表区无 AppBar）。
  Widget _buildWidePanel(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final bg = _bg;
    final fg = _fg;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bg, CoverPalette.darken(bg, 0.35)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // 顶部返回条：AppBar 只占左列
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onBack,
                    tooltip: '返回',
                    icon: Icon(Icons.arrow_back_rounded, color: fg),
                  ),
                  Expanded(
                    child: Text(widget.name,
                        style: tt.titleMedium?.copyWith(color: fg),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: fg.withValues(alpha: 0.2)),
            // 内容区：封面充满面板宽度
            Expanded(
              child: LayoutBuilder(
                builder: (context, cons) {
                  final coverSize = (cons.maxWidth - AppSpacing.s16 * 2)
                      .clamp(120.0, 320.0)
                      .toDouble();
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.s16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _cover(context, size: coverSize),
                        const SizedBox(height: AppSpacing.s16),
                        Text(widget.name,
                            style: tt.headlineSmall?.copyWith(color: fg),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: AppSpacing.s8),
                          Text(widget.subtitle!,
                              style: tt.bodyMedium
                                  ?.copyWith(color: fg.withValues(alpha: 0.75)),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ],
                        const SizedBox(height: AppSpacing.s16),
                        FilledButton.icon(
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('播放全部'),
                          onPressed: widget.onPlayAll,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 封面 ====================

  Widget _cover(BuildContext context, {required double size}) {
    final cs = Theme.of(context).colorScheme;

    // 占位：favorite 用心形主题封面，否则音符占位
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: widget.isFavorite
            ? cs.primaryContainer
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.s16),
      ),
      child: Icon(
        widget.isFavorite ? Icons.favorite_rounded : Icons.queue_music_rounded,
        color: widget.isFavorite ? cs.onPrimaryContainer : cs.onSurfaceVariant,
        size: size * 0.4,
      ),
    );

    if (widget.isFavorite) return placeholder;
    final url = widget.coverUrl;
    if (url == null || url.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.s16),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return placeholder;
        },
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}
