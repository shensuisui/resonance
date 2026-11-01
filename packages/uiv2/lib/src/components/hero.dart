/// 详情页英雄区（.hero / .hero__art / .hero__type / .hero__title / .hero__meta /
/// .hero__actions）—— 专辑、艺人、歌单、我喜欢的共用。
library;

import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/typography.dart';

/// 英雄区
class UiV2Hero extends StatelessWidget {
  /// 封面（正方形）
  final Widget art;

  /// 类型标签（专辑 / 艺人 / 歌单 / 收藏）
  final String type;

  /// 主标题
  final String title;

  /// 元信息
  final String meta;

  /// 动作按钮行
  final List<Widget> actions;

  /// 构造英雄区
  const UiV2Hero({
    super.key,
    required this.art,
    required this.type,
    required this.title,
    required this.meta,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < UiV2Breakpoints.wide;

    final artSize = narrow
        ? (width * 0.56).clamp(120.0, 220.0)
        : 220.0;

    final artBox = SizedBox(
      width: artSize,
      height: artSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: UiV2Radii.brLg,
          boxShadow: t.shadow3,
          color: t.surface2,
        ),
        child: ClipRRect(borderRadius: UiV2Radii.brLg, child: art),
      ),
    );

    final text = Column(
      crossAxisAlignment:
          narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          type,
          style: UiV2Text.capsLabel.copyWith(color: t.textDim),
          textAlign: narrow ? TextAlign.center : TextAlign.start,
        ),
        const SizedBox(height: UiV2Spacing.s2),
        Text(
          title,
          style: UiV2Text.heroTitle.copyWith(color: t.text),
          textAlign: narrow ? TextAlign.center : TextAlign.start,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: UiV2Spacing.s3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Text(
            meta,
            style: UiV2Text.bodyDim.copyWith(color: t.textDim),
            textAlign: narrow ? TextAlign.center : TextAlign.start,
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: UiV2Spacing.s5),
          Wrap(
            spacing: UiV2Spacing.s2,
            runSpacing: UiV2Spacing.s2,
            alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ],
      ],
    );

    if (narrow) {
      return Padding(
        padding: const EdgeInsets.only(bottom: UiV2Spacing.s5),
        child: Column(
          children: [
            artBox,
            const SizedBox(height: UiV2Spacing.s4),
            text,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: UiV2Spacing.s6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          artBox,
          const SizedBox(width: UiV2Spacing.s5),
          Expanded(child: text),
        ],
      ),
    );
  }
}
