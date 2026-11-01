/// 页面骨架 —— 对应原型的 .page / .page--detail / .page__head / .page__sub
/// 与断点决定的 --gutter（16 / 24 / 32 / 40）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/tokens.dart';
import '../design/typography.dart';

/// 页面左右留白（--gutter）
double uiV2GutterFor(double width) {
  if (width >= UiV2Breakpoints.large) return 40;
  if (width >= UiV2Breakpoints.desktop) return 32;
  if (width >= UiV2Breakpoints.wide) return 24;
  return 16;
}

/// 页面骨架：滚动容器 + 最大宽度 + 留白
class PageShell extends ConsumerWidget {
  /// 页面内容
  final Widget child;

  /// 是否为滚动容器（详情页在窄屏把搜索框之类钉在顶部的场景不需要外层滚动）
  final bool scrollable;

  /// 顶部额外留白倍数（详情页 padding-top 16）
  final double topPadding;

  /// 构造页面骨架
  const PageShell({
    super.key,
    required this.child,
    this.scrollable = true,
    this.topPadding = UiV2Spacing.s5,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final gutter = uiV2GutterFor(width);
    // 平板档（768–1023）内容区上移让出浮动返回键（原型 .view{padding-top:72px}）
    final floatBackSpace =
        width >= UiV2Breakpoints.wide && width < UiV2Breakpoints.desktop;

    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        gutter,
        topPadding + (floatBackSpace ? 56 : 0),
        gutter,
        UiV2Spacing.s8,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width >= UiV2Breakpoints.large
              ? UiV2Metrics.contentMaxLarge
              : UiV2Metrics.contentMax,
        ),
        child: child,
      ),
    );

    return scrollable
        ? SingleChildScrollView(
            primary: false,
            child: Align(alignment: Alignment.topCenter, child: content),
          )
        : Align(alignment: Alignment.topCenter, child: content);
  }
}

/// 页面头部（.page__head）
class PageHead extends StatelessWidget {
  /// 主标题
  final String title;

  /// 副标题
  final String? sub;

  /// 右侧动作（按钮 / 更多）
  final Widget? action;

  /// 紧凑标题（.page__head--compact，22px）
  final bool compact;

  /// 构造页面头部
  const PageHead({
    super.key,
    required this.title,
    this.sub,
    this.action,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < UiV2Breakpoints.wide;
    final t = UiV2Theme.of(context);

    final titleBlock = Column(
      crossAxisAlignment:
          narrow ? CrossAxisAlignment.start : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: (compact ? UiV2Text.sectionTitle : UiV2Text.pageTitle)
              .copyWith(color: t.text),
        ),
        if (sub != null && sub!.isNotEmpty) ...[
          const SizedBox(height: UiV2Spacing.s2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              sub!,
              style: UiV2Text.bodyDim.copyWith(color: t.textDim),
            ),
          ),
        ],
      ],
    );

    if (narrow) {
      return Padding(
        padding: const EdgeInsets.only(bottom: UiV2Spacing.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            titleBlock,
            if (action != null) ...[
              const SizedBox(height: UiV2Spacing.s4),
              action!,
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: UiV2Spacing.s5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: titleBlock),
          if (action != null) ...[
            const SizedBox(width: UiV2Spacing.s4),
            action!,
          ],
        ],
      ),
    );
  }
}

/// 纯文本块（用于简易说明段）
class PageBody extends StatelessWidget {
  /// 子组件
  final Widget child;

  /// 构造内容块
  const PageBody({super.key, required this.child});

  @override
  Widget build(BuildContext context) => PageShell(child: child);
}
