/// 搜索页（原型 renderSearch / searchIdleHtml / searchResultsHtml）
///
/// 与原型一致的行为：输入即时搜索、来源筛选条、默认只显示 10 条并可展开、
/// 空关键词时展示「最近搜索 / 推荐搜索」。
/// 数据来源换成真实的聚合搜索（[searchProvider] → SourceManager.searchAll）：
///   * 结果 = [SearchState].pools（按来源分组的真实 [Song]）；
///   * 历史 = [searchHistoryProvider]（settings 真实持久化）；
///   * 推荐词 = 演示曲库的艺人名 + 真实推荐歌单名，不再虚构热度。
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/rows.dart';
import '../components/sheets.dart';
import '../components/surfaces.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../providers/providers.dart';
import '../router.dart';
import '../widgets/page_shell.dart';
import '../widgets/track_actions.dart';

/// 搜索页
class SearchPage extends ConsumerStatefulWidget {
  /// 构造搜索页
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchProvider);

    return PageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHead(
            title: '搜索歌曲',
            sub: '一次搜索所有已启用的音乐源，结果聚合展示，每行标出来源。',
          ),
          _SearchBar(
            controller: _input,
            focusNode: _focus,
            hasText: state.keyword.isNotEmpty,
            onChanged: _onChanged,
            onSubmit: _onSubmit,
            onClear: _onClear,
          ),
          const SizedBox(height: UiV2Spacing.s5),
          if (state.keyword.isEmpty)
            _SearchIdle(onPick: _onPick)
          else
            _SearchResults(state: state),
        ],
      ),
    );
  }

  /// 输入变化：**1000ms** 防抖后搜索（用户定的时长，避免逐字符触发远程聚合）
  ///
  /// 这里**不写搜索历史**：否则「a / ab / abc」这类中间前缀都会被记进去。
  ///
  /// 注意防抖只管少发请求，**不保证结果与输入一致** —— 那个保证
  /// 在 [SearchNotifier.search] 的请求令牌上（过期请求的结果一律丢弃）。
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1000), () => _run(value));
  }

  /// 回车确认：真正执行搜索并记一条历史
  void _onSubmit(String value) {
    _debounce?.cancel();
    _run(value, recordHistory: true);
  }

  /// 点历史 / 推荐词 / 分类：回填输入框后立刻搜索，并记历史
  void _onPick(String word) {
    _debounce?.cancel();
    _input.value = TextEditingValue(
      text: word,
      selection: TextSelection.collapsed(offset: word.length),
    );
    _run(word, recordHistory: true);
  }

  /// 清空输入与结果
  void _onClear() {
    _input.clear();
    ref.read(searchProvider.notifier).clear();
    _focus.requestFocus();
  }

  /// 统一走真实聚合搜索（空关键词由 notifier 自己复位成 idle 状态）
  void _run(String value, {bool recordHistory = false}) {
    unawaited(
      ref
          .read(searchProvider.notifier)
          .search(value, recordHistory: recordHistory),
    );
  }
}

/// 来源筛选条
///
/// 顺序即语义：已返回的源按**返回顺序**排在前面（先回来先上屏），
/// 还没返回的源保持默认顺序、名字前显示 loading —— 排序由 Provider 负责，
/// 这里只如实渲染，不自己算。
class _SourceChips extends ConsumerWidget {
  /// 当前搜索状态
  final SearchState state;

  /// 构造来源条
  const _SourceChips({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          UiV2Chip(
            label: '全部来源',
            selected: state.sourceFilter == 'all',
            onTap: () =>
                ref.read(searchProvider.notifier).setSourceFilter('all'),
          ),
          for (final pool in state.pools) ...[
            const SizedBox(width: UiV2Spacing.s2),
            UiV2Chip(
              label: pool.name,
              // 还在搜的源：名字前转圈，回来即换成结果
              leading: pool.loading
                  ? UiV2Spinner(
                      trackColor: t.surface3,
                      color: t.accent,
                      size: 12,
                    )
                  : null,
              selected: state.sourceFilter == pool.id,
              onTap: () =>
                  ref.read(searchProvider.notifier).setSourceFilter(pool.id),
            ),
          ],
        ],
      ),
    );
  }
}

/// 搜索输入条（.searchbar）
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasText;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.hasText,
    required this.onChanged,
    required this.onSubmit,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: UiV2Spacing.s4),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.line),
        borderRadius: UiV2Radii.brPill,
      ),
      child: Row(
        children: [
          UiV2Icon(UiV2Icons.search, size: 22, color: t.textMute),
          const SizedBox(width: UiV2Spacing.s3),
          Expanded(
            child: TextField(
              key: const ValueKey('search_input'),
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              onSubmitted: onSubmit,
              textInputAction: TextInputAction.search,
              style: UiV2Text.body.copyWith(color: t.text),
              cursorColor: t.accent,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '搜索歌曲',
                hintStyle: UiV2Text.body.copyWith(color: t.textMute),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: UiV2Spacing.s4,
                ),
              ),
            ),
          ),
          if (hasText)
            UiV2IconButton(
              icon: UiV2Icons.close,
              semanticLabel: '清空搜索',
              onTap: onClear,
            ),
        ],
      ),
    );
  }
}

/// 空关键词内容：最近搜索 / 推荐搜索 / 浏览分类
class _SearchIdle extends ConsumerWidget {
  /// 点选词条后的回调（回填输入框 + 立即搜索）
  final ValueChanged<String> onPick;

  /// 构造内容
  const _SearchIdle({required this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 最近搜索：settings 里的真实历史
    final history = ref.watch(searchHistoryProvider);

    // 推荐词：曲库里真实的艺人名 + 各源真实推荐歌单名（原型 hotSearches 的做法）
    final words = <String>[
      ...ref.watch(catalogProvider).artists.map((a) => a.name),
      ...(ref.watch(recommendedPlaylistsProvider).value ?? const <Playlist>[])
          .map((p) => p.name),
    ];
    final hot = <String>[];
    for (final word in words) {
      if (hot.length >= 6) break;
      if (word.isEmpty || hot.contains(word)) continue;
      hot.add(word);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (history.isNotEmpty)
          UiV2Section(
            title: '最近搜索',
            linkText: '清空',
            onLinkTap: () {
              ref.read(searchHistoryProvider.notifier).clear();
              showUiV2Toast(context, '已清空搜索历史');
            },
            child: Wrap(
              spacing: UiV2Spacing.s2,
              runSpacing: UiV2Spacing.s2,
              children: [
                for (final word in history)
                  UiV2Chip(
                    label: word,
                    icon: UiV2Icons.clock,
                    onTap: () => onPick(word),
                  ),
              ],
            ),
          ),
        if (hot.isNotEmpty)
          UiV2Section(
            title: '推荐搜索',
            child: Wrap(
              spacing: UiV2Spacing.s2,
              runSpacing: UiV2Spacing.s2,
              children: [
                for (final word in hot)
                  UiV2Chip(label: word, onTap: () => onPick(word)),
              ],
            ),
          ),
      ],
    );
  }
}

/// 搜索结果（原型 searchResultsHtml）
class _SearchResults extends ConsumerWidget {
  /// 当前搜索状态（关键词 / 分组 / 筛选 / 展开）
  final SearchState state;

  /// 构造结果
  const _SearchResults({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final enabled = ref.watch(enabledSourcesProvider);
    // 展示元数据：封面 / 时长（曲目一律是真实 Song）
    final meta = ref.watch(catalogTracksProvider);
    final keyword = state.keyword;
    final total = state.total;

    final header = Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: '共 '),
                TextSpan(
                  text: '$total',
                  style: UiV2Text.trackTitle.copyWith(color: t.text),
                ),
                TextSpan(text: ' 首与「$keyword」相关的歌曲'),
              ],
            ),
            style: UiV2Text.hint.copyWith(color: t.textDim),
          ),
        ),
        UiV2GhostMini(
          label: '清除',
          icon: UiV2Icons.close,
          onTap: () => ref.read(searchProvider.notifier).clear(),
        ),
      ],
    );

    // 聚合搜索只查已启用的源：全部停用时给出可操作的引导
    if (enabled.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: UiV2Spacing.s4),
          UiV2Panel(
            child: UiV2Empty(
              title: '所有音乐源都已停用',
              text: '聚合搜索只查已启用的源。去「音乐源」重新打开一个，或通过订阅添加新源。',
              icon: UiV2Icons.globe,
              actions: UiV2Button(
                label: '管理音乐源',
                variant: UiV2ButtonVariant.primary,
                onTap: () => ref.read(navProvider.notifier).go('sources'),
              ),
            ),
          ),
        ],
      );
    }

    // 逐源渐进：来源条**立刻**出来（每个源名前的 loading 由所在分组自己控制），
    // 结果还没到时也不整页空白 —— 用户要求「不要等所有源请求完再显示」。
    if (state.loading && state.filteredTotal == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: UiV2Spacing.s3),
          _SourceChips(state: state),
          const SizedBox(height: UiV2Spacing.s4),
          UiV2Panel(
            child: Padding(
              padding: const EdgeInsets.all(UiV2Spacing.s8),
              child: Center(
                child: UiV2Spinner(trackColor: t.surface3, color: t.accent),
              ),
            ),
          ),
        ],
      );
    }

    // 必须要求 !loading：搜索途中「还没有任何结果」不等于「没有找到」
    // （上面那个 loading 分支负责搜索中的空结果区，这里只判尘埃落定后的空）
    if (!state.loading && total == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: UiV2Spacing.s4),
          UiV2Panel(
            child: UiV2Empty(
              title: '没有找到「$keyword」',
              text: '换个关键词试试，或检查拼写。',
              icon: UiV2Icons.search,
              actions: UiV2Button(
                label: '清除关键词',
                variant: UiV2ButtonVariant.soft,
                onTap: () => ref.read(searchProvider.notifier).clear(),
              ),
            ),
          ),
        ],
      );
    }

    final visible = state.visibleSongs(limit: 10);
    final active = state.activePools;
    final activeCount = active.length;
    final sectionTitle = activeCount > 1
        ? '来自 $activeCount 个源'
        : (activeCount == 1 ? active.first.name : '全部来源');
    final mergedCount = state.filteredTotal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: UiV2Spacing.s3),
        // 来源筛选条（.chip[aria-pressed]）：顺序来自 state.pools
        // —— 已返回的源按返回顺序在前，未返回的保持默认顺序，未返回的源名带 loading
        _SourceChips(state: state),
        const SizedBox(height: UiV2Spacing.s4),
        if (visible.isEmpty)
          UiV2Panel(
            child: UiV2Empty(
              title: '这个来源没有「$keyword」的结果',
              text: '切回「全部来源」看看其它源，或换个关键词。',
              icon: UiV2Icons.search,
            ),
          )
        else
          UiV2Section(
            title: sectionTitle,
            linkText: state.anyLoading ? '$mergedCount 首 · 搜索中' : '$mergedCount 首',
            child: UiV2Panel(
              child: Column(
                children: [
                  UiV2TrackList(
                    rows: [
                      for (var i = 0; i < visible.length; i++)
                        UiV2SongRow(
                          song: visible[i],
                          meta: meta[visible[i].id],
                          index: i,
                          showArt: true,
                          highlight: keyword,
                          // 搜索候选不是播放队列：记入最近播放并切到最近播放
                          onTap: () => TrackActions.playAsRecent(
                              context, ref, visible[i]),
                          onToggleLike: () => TrackActions.toggleLike(
                            context,
                            ref,
                            visible[i],
                          ),
                          onMore: () => showTrackMenu(
                            context,
                            trackId: visible[i].globalKey,
                          ),
                        ),
                    ],
                  ),
                  if (mergedCount > 10)
                    Container(
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: t.line)),
                      ),
                      padding: const EdgeInsets.all(UiV2Spacing.s4),
                      child: UiV2Button(
                        label: state.expanded
                            ? '收起'
                            : '显示全部 $mergedCount 首',
                        variant: UiV2ButtonVariant.soft,
                        block: true,
                        onTap: () =>
                            ref.read(searchProvider.notifier).toggleExpanded(),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
