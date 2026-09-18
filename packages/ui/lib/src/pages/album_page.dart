/// 专辑页 —— 按专辑名聚合该专辑的歌曲
///
/// 布局对齐歌单详情页（PlaylistHeaderView）：
/// - 手机/竖屏：CustomScrollView + SliverAppBar（可伸缩），头部为
///   封面主题色渐变 + 名称/歌手/数量 + 大号播放全部按钮
/// - 宽屏/横屏：Row 布局，左侧 PlaylistHeaderView 完整面板 + 右列列表
///
/// 当前规则源无专辑 ID 规则，采用按专辑名搜索 + 过滤的实现方式。
/// 封面取色源：列表首曲封面（无专辑封面数据）。
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import '../providers/providers.dart';
import '../theme/app_spacing.dart';
import '../widgets/song_tile.dart';
import '../widgets/playlist_header.dart';
import '../widgets/cover_palette.dart';
import '../widgets/empty_state.dart';

class AlbumPage extends ConsumerStatefulWidget {
  final String albumName;
  final String? artistName;

  const AlbumPage({super.key, required this.albumName, this.artistName});

  @override
  ConsumerState<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends ConsumerState<AlbumPage> {
  List<Song> _songs = [];
  bool _loading = true;
  String? _error;

  /// 封面主题色（折叠态背景/前景用，对齐歌单详情页）
  Color? _headerColor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final manager = ref.read(sourceManagerProvider);
      final results = await manager.searchAll(keyword: widget.albumName);
      // 过滤：专辑名匹配（+ 歌手名匹配，可选）
      final albumKeyword = widget.albumName.toLowerCase();
      final songs = results
          .expand((r) => r.songs)
          .where((s) {
            final matchAlbum =
                s.album?.toLowerCase().contains(albumKeyword) ?? false;
            if (widget.artistName != null && matchAlbum) {
              return s.artist
                  .toLowerCase()
                  .contains(widget.artistName!.toLowerCase());
            }
            return matchAlbum;
          })
          .toList();
      if (!mounted) return;
      setState(() {
        _songs = songs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 列表第一首有封面的歌曲封面 URL（头部取色源）
  String? get _firstCoverUrl {
    for (final s in _songs) {
      if (s.coverUrl != null && s.coverUrl!.isNotEmpty) return s.coverUrl;
    }
    return null;
  }

  String get _subtitle {
    final parts = <String>[];
    if (widget.artistName != null && widget.artistName!.isNotEmpty) {
      parts.add(widget.artistName!);
    }
    parts.add('${_songs.length} 首歌曲');
    return parts.join(' · ');
  }

  /// 播放全部
  void _playAll() {
    if (_songs.isEmpty) return;
    final player = ref.read(playerProvider);
    player.setQueue(_songs);
    player.jumpToIndex(0);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // 加载/错误/空三态没有 SliverAppBar，需补常驻 AppBar 提供标题与返回按钮
    final needBar = _loading || _error != null || _songs.isEmpty;

    return Scaffold(
      appBar: needBar ? AppBar(title: Text(widget.albumName)) : null,
      body: _buildBody(cs, tt),
    );
  }

  Widget _buildBody(ColorScheme cs, TextTheme tt) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      // 错误态统一走 EmptyState.error（图标 + 文案 + 重试三件套）
      return EmptyState.error(
        message: '加载失败',
        detail: _error,
        onRetry: _load,
      );
    }
    if (_songs.isEmpty) {
      return const EmptyState(
        icon: Icons.album_rounded,
        message: '未找到相关歌曲',
      );
    }

    return OrientationBuilder(
      builder: (context, orientation) {
        final isWide = orientation == Orientation.landscape;
        if (isWide) return _buildWide(cs);
        return _buildNarrow(cs, tt);
      },
    );
  }

  // ==================== 竖屏：SliverAppBar 可伸缩头部 ====================

  Widget _buildNarrow(ColorScheme cs, TextTheme tt) {
    final headerBg = _headerColor ?? cs.surfaceContainerLow;
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            // 头部高度与歌单详情页统一（有封面 320 / 无封面 264）
            expandedHeight: (_firstCoverUrl != null) ? 320 : 264,
            backgroundColor: headerBg,
            foregroundColor: _headerColor == null
                ? null
                : CoverPalette.foreground(_headerColor!),
            title: Text(widget.albumName,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: PlaylistHeaderView(
                mode: PlaylistHeaderMode.flexible,
                name: widget.albumName,
                coverUrl: _firstCoverUrl,
                subtitle: _subtitle,
                onPlayAll: _songs.isEmpty ? null : _playAll,
                onColorExtracted: (color) {
                  if (!mounted) return;
                  setState(() => _headerColor = color);
                },
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: AppSpacing.s8)),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final song = _songs[index];
                return SongTile(song: song);
              },
              childCount: _songs.length,
            ),
          ),
          // 底部留白：浮层迷你条遮挡补偿
          const SliverToBoxAdapter(
            child: SizedBox(height: AppSpacing.s64 + AppSpacing.s8),
          ),
        ],
      ),
    );
  }

  // ==================== 宽屏：左信息面板 + 右列表 ====================

  Widget _buildWide(ColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 300,
          child: PlaylistHeaderView(
            mode: PlaylistHeaderMode.wide,
            name: widget.albumName,
            coverUrl: _firstCoverUrl,
            subtitle: _subtitle,
            onPlayAll: _songs.isEmpty ? null : _playAll,
            onBack: () => Navigator.pop(context),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          // 宽屏同样支持下拉刷新，与竖屏能力一致
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _songs.length,
              itemBuilder: (context, index) {
                final song = _songs[index];
                return SongTile(song: song);
              },
            ),
          ),
        ),
      ],
    );
  }
}
