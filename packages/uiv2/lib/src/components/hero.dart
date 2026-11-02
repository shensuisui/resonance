/// 详情页英雄区（.hero / .hero__art / .hero__type / .hero__title / .hero__meta /
/// .hero__actions）—— 专辑、艺人、歌单、我喜欢的共用。
library;

import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
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

/// 操作栏的一项
@immutable
class UiV2ActionItem {
  /// 图标名（见 [UiV2Icons]）
  final String icon;

  /// 文案
  final String label;

  /// 点击回调
  final VoidCallback onTap;

  /// 测试 / 驱动用的 key
  final Key? key;

  /// 构造一项
  const UiV2ActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.key,
  });
}

/// 详情页操作栏（原型没有，参考漫画详情页的 .actions）
///
/// 排布：**通栏 + 各项等分 + 图标在上文字在下**。
/// 颜色一律次级灰，不做主色高亮 —— 与参考页一致：它把「当前状态」用主色，
/// 而不是把某项标成主按钮；详情页的主行动由封面右侧的统计行承担。
/// 也没有边框/底色：它不是按钮，是一排动作入口（点击态只给一层淡底）。
class UiV2ActionBar extends StatelessWidget {
  /// 各项动作（顺序即左到右）
  final List<UiV2ActionItem> items;

  /// 构造操作栏
  const UiV2ActionBar({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return Row(
      children: [
        for (final item in items)
          Expanded(
            child: UiV2Pressable(
              key: item.key,
              onTap: item.onTap,
              radius: UiV2Radii.brMd,
              hoverColor: t.surface2,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    UiV2Icon(item.icon, size: 22, color: t.textDim),
                    const SizedBox(height: UiV2Spacing.s1),
                    Text(
                      item.label,
                      style: UiV2Text.hint.copyWith(color: t.textDim),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 详情页手机端头部：封面 + 文字 + 操作栏
///
/// 排布照参考页：封面与文字左右并排（文字列里**不再塞按钮**），
/// 操作栏独占一行通栏排在信息块下面。这样封面尺寸只受屏宽约束，
/// 不会因为要塞下两个按钮而被迫在窄屏缩水或换行。
class UiV2DetailHeader extends StatelessWidget {
  /// 封面内容（正方形，由本组件负责尺寸/圆角/投影/裁切）
  final Widget art;

  /// 类型标签（歌单 · 我的 / 收藏 …）
  final String type;

  /// 主统计行（N 首 · M 分钟）
  final String line1;

  /// 次级行（在线 X · 本地 Y / 更新于 …）；空则不渲染
  final String? line2;

  /// 操作栏各项
  final List<UiV2ActionItem> actions;

  /// 构造头部
  const UiV2DetailHeader({
    super.key,
    required this.art,
    required this.type,
    required this.line1,
    this.line2,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    // 与 UiV2Hero 的窄屏封面尺寸保持一致，不再缩小
    final artSize = (width * 0.56).clamp(120.0, 220.0);
    final second = line2 ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: UiV2Spacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            // 文字列相对封面**垂直居中**：贴顶会让右侧三行挤在顶上、下面空一大截
            // （用户指出「有点太偏上了」）。封面是本行最高元素，居中即相对正方形中间对齐。
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                key: const ValueKey('detail_header_art'),
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
                    child: art,
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
                      line1,
                      style: UiV2Text.bodyDim.copyWith(color: t.textDim),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (second.isNotEmpty)
                      Text(
                        second,
                        style: UiV2Text.hint.copyWith(color: t.textDim),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: UiV2Spacing.s4),
            UiV2ActionBar(items: actions),
          ],
        ],
      ),
    );
  }
}
