/// 基础容器与控件 —— 对应原型的 .panel / .btn / .chip / .badge / .segmented /
/// .empty / .searchbar / .switch / .list-row / .stat / .folder-ico / .sleep-now /
/// .scan-status / .cat / .track__grip 等可复用外观件。
///
/// 所有尺寸与颜色都取自设计令牌，逐条对应 styles.css 的声明。
library;

import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';

/// 面板（.panel）：surface 底 + 1px 描边 + 16 圆角 + 裁剪溢出
class UiV2Panel extends StatelessWidget {
  /// 子组件
  final Widget child;

  /// 内边距（.panel__pad 为 16）
  final EdgeInsetsGeometry? padding;

  /// 构造面板
  const UiV2Panel({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.line),
        borderRadius: UiV2Radii.brLg,
      ),
      clipBehavior: Clip.antiAlias,
      padding: padding,
      child: child,
    );
  }
}

/// 区块（.section + .section__head）：标题 + 可选「查看全部」
class UiV2Section extends StatelessWidget {
  /// 区块标题
  final String title;

  /// 右上角链接文案（为空则不显示）
  final String? linkText;

  /// 右上角链接点击
  final VoidCallback? onLinkTap;

  /// 区块内容
  final Widget child;

  /// 构造区块
  const UiV2Section({
    super.key,
    required this.title,
    required this.child,
    this.linkText,
    this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: UiV2Spacing.s7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: UiV2Spacing.s4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: UiV2Text.sectionTitle.copyWith(color: t.text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (linkText != null && linkText!.isNotEmpty)
                  UiV2Pressable(
                    onTap: onLinkTap,
                    child: Text(
                      linkText!,
                      style: UiV2Text.buttonSmall.copyWith(color: t.textDim),
                    ),
                  ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// 文字按钮的三个变体（.btn--primary / --soft / --outline / --danger）
enum UiV2ButtonVariant {
  /// 强调色实心
  primary,

  /// 二级表面 + 描边
  soft,

  /// 透明底 + 强描边
  outline,

  /// 危险色实心
  danger,
}

/// 文字按钮（.btn）
class UiV2Button extends StatefulWidget {
  /// 文案
  final String label;

  /// 前置图标（可选）
  final String? icon;

  /// 变体
  final UiV2ButtonVariant variant;

  /// 点击回调（null 表示禁用）
  final VoidCallback? onTap;

  /// 是否撑满宽度（.btn--block）
  final bool block;

  /// 紧凑内边距（移动端 hero 区的 .btn{padding:0 16px}）
  final bool compact;

  /// 构造按钮
  const UiV2Button({
    super.key,
    required this.label,
    this.icon,
    this.variant = UiV2ButtonVariant.soft,
    this.onTap,
    this.block = false,
    this.compact = false,
  });

  @override
  State<UiV2Button> createState() => _UiV2ButtonState();
}

class _UiV2ButtonState extends State<UiV2Button> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final disabled = widget.onTap == null;

    final (Color bg, Color fg, Color? border) = switch (widget.variant) {
      UiV2ButtonVariant.primary => (t.accent, t.accentInk, null),
      UiV2ButtonVariant.soft => (
          _hover ? t.surface3 : t.surface2,
          t.text,
          t.line,
        ),
      UiV2ButtonVariant.outline => (
          const Color(0x00000000),
          t.text,
          _hover ? t.textDim : t.lineStrong,
        ),
      UiV2ButtonVariant.danger => (t.danger, t.accentInk, null),
    };

    final content = AnimatedContainer(
      duration: UiV2Motion.d1,
      curve: UiV2Motion.enter,
      constraints: const BoxConstraints(minHeight: 44),
      padding: EdgeInsets.symmetric(horizontal: widget.compact ? UiV2Spacing.s4 : UiV2Spacing.s5),
      decoration: BoxDecoration(
        color: bg,
        border: border == null ? null : Border.all(color: border),
        borderRadius: UiV2Radii.brPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.icon != null) ...[
            UiV2Icon(widget.icon!, size: 18, color: fg),
            const SizedBox(width: UiV2Spacing.s2),
          ],
          Text(
            widget.label,
            style: UiV2Text.button.copyWith(color: fg),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    final wrapped = widget.block
        ? SizedBox(width: double.infinity, child: content)
        : content;

    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: MouseRegion(
        cursor: disabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: UiV2Pressable(
          onTap: widget.onTap,
          pressedScale: 0.98,
          enabled: !disabled,
          child: wrapped,
        ),
      ),
    );
  }
}

/// 幽灵小按钮（.ghost-mini，可带危险态）
class UiV2GhostMini extends StatelessWidget {
  /// 文案
  final String label;

  /// 图标名
  final String? icon;

  /// 危险变体
  final bool danger;

  /// 点击回调
  final VoidCallback? onTap;

  /// 构造幽灵小按钮
  const UiV2GhostMini({
    super.key,
    required this.label,
    this.icon,
    this.danger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final color = danger ? t.danger : t.textDim;
    return UiV2Pressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: UiV2Spacing.s3),
        decoration: BoxDecoration(
          border: Border.all(color: t.line),
          borderRadius: UiV2Radii.brPill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              UiV2Icon(icon!, size: 17, color: color),
              const SizedBox(width: 6),
            ],
            Text(label, style: UiV2Text.buttonSmall.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

/// 可点标签（.chip）
class UiV2Chip extends StatelessWidget {
  /// 文案
  final String label;

  /// 图标名
  final String? icon;

  /// 是否选中（对应 aria-pressed=true）
  final bool selected;

  /// 点击回调
  final VoidCallback? onTap;

  /// 构造标签
  const UiV2Chip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final fg = selected ? t.bg : t.textDim;
    return UiV2Pressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: UiV2Spacing.s4),
        decoration: BoxDecoration(
          color: selected ? t.text : t.surface,
          border: Border.all(color: selected ? t.text : t.line),
          borderRadius: UiV2Radii.brPill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              UiV2Icon(icon!, size: 14, color: fg),
              const SizedBox(width: 6),
            ],
            Text(label, style: UiV2Text.buttonSmall.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}

/// 徽标（.badge，含 accent / ok / glass 变体）
enum UiV2BadgeTone {
  /// 默认：surface-3 底
  plain,

  /// 强调色浅底
  accent,

  /// 成功色浅底
  ok,

  /// 半透明黑底（卡片封面上的「我的」）
  glass,
}

/// 徽标
class UiV2Badge extends StatelessWidget {
  /// 文案
  final String label;

  /// 图标名
  final String? icon;

  /// 色调
  final UiV2BadgeTone tone;

  /// 构造徽标
  const UiV2Badge({
    super.key,
    required this.label,
    this.icon,
    this.tone = UiV2BadgeTone.plain,
  });

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final (Color bg, Color fg) = switch (tone) {
      UiV2BadgeTone.plain => (t.surface3, t.textDim),
      UiV2BadgeTone.accent => (t.accentSoft, t.accent),
      UiV2BadgeTone.ok => (t.ok.withValues(alpha: 0.16), t.ok),
      UiV2BadgeTone.glass => (const Color(0x80000000), const Color(0xFFFFFFFF)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: UiV2Radii.brPill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            UiV2Icon(icon!, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label, style: UiV2Text.badge.copyWith(color: fg)),
        ],
      ),
    );
  }
}

/// 分段控件（.segmented + .seg）
class UiV2Segmented extends StatelessWidget {
  /// 选项（id → 文案）
  final List<(String, String)> options;

  /// 当前选中 id
  final String value;

  /// 选择回调
  final ValueChanged<String> onChanged;

  /// 构造分段控件
  const UiV2Segmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: UiV2Spacing.s5),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: t.surface2,
          border: Border.all(color: t.line),
          borderRadius: UiV2Radii.brPill,
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (id, label) in options) ...[
                const SizedBox(width: 4),
                _Segment(
                  label: label,
                  selected: id == value,
                  onTap: () => onChanged(id),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Segment({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return UiV2Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: UiV2Motion.d1,
        curve: UiV2Motion.enter,
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: UiV2Spacing.s4),
        decoration: BoxDecoration(
          color: selected ? t.surface : const Color(0x00000000),
          borderRadius: UiV2Radii.brPill,
          boxShadow: selected ? t.shadow1 : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: UiV2Text.rowLabel.copyWith(
            color: selected ? t.text : t.textDim,
          ),
        ),
      ),
    );
  }
}

/// 空态（.empty）
class UiV2Empty extends StatelessWidget {
  /// 标题
  final String title;

  /// 说明文案
  final String? text;

  /// 图标名
  final String icon;

  /// 操作区（按钮等）
  final Widget? actions;

  /// 构造空态
  const UiV2Empty({
    super.key,
    required this.title,
    this.text,
    this.icon = UiV2Icons.note,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: UiV2Spacing.s4,
        vertical: UiV2Spacing.s8,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: UiV2Radii.brPill,
            ),
            alignment: Alignment.center,
            child: UiV2Icon(icon, size: 26, color: t.textMute),
          ),
          const SizedBox(height: UiV2Spacing.s3),
          Text(title, style: UiV2Text.emptyTitle.copyWith(color: t.text)),
          if (text != null && text!.isNotEmpty) ...[
            const SizedBox(height: UiV2Spacing.s3),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Text(
                text!,
                textAlign: TextAlign.center,
                style: UiV2Text.bodyDim.copyWith(color: t.textDim),
              ),
            ),
          ],
          if (actions != null) ...[
            const SizedBox(height: UiV2Spacing.s2),
            actions!,
          ],
        ],
      ),
    );
  }
}

/// 列表行（.list-row）：主文案 + 提示 + 尾部控件
class UiV2ListRow extends StatelessWidget {
  /// 主文案
  final String label;

  /// 提示文案
  final String? hint;

  /// 提示色（日志行用 warn / danger）
  final Color? hintColor;

  /// 前置控件（如 .folder-ico）
  final Widget? leading;

  /// 尾部控件
  final Widget? trailing;

  /// 点击回调
  final VoidCallback? onTap;

  /// 是否显示下分隔线（最后一行不显示）
  final bool divider;

  /// 构造列表行
  const UiV2ListRow({
    super.key,
    required this.label,
    this.hint,
    this.hintColor,
    this.leading,
    this.trailing,
    this.onTap,
    this.divider = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return UiV2Pressable(
      onTap: onTap,
      radius: UiV2Radii.brMd,
      hoverColor: onTap == null ? null : t.surface2,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(
          horizontal: UiV2Spacing.s4,
          vertical: UiV2Spacing.s3,
        ),
        decoration: BoxDecoration(
          border: divider
              ? Border(bottom: BorderSide(color: t.line))
              : null,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: UiV2Spacing.s4),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: UiV2Text.rowLabel.copyWith(color: t.text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hint != null && hint!.isNotEmpty)
                    Text(
                      hint!,
                      style: UiV2Text.hint.copyWith(color: hintColor ?? t.textDim),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: UiV2Spacing.s4),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 行尾「进入」箭头（列表行右侧的 chevron-right）
class UiV2Chevron extends StatelessWidget {
  /// 构造箭头
  const UiV2Chevron({super.key});

  @override
  Widget build(BuildContext context) =>
      UiV2Icon(UiV2Icons.chevronRight, size: 20, color: UiV2Theme.of(context).textMute);
}

/// 文件夹图标块（.folder-ico）
class UiV2FolderIcon extends StatelessWidget {
  /// 构造文件夹图标
  const UiV2FolderIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: t.surface3,
        borderRadius: UiV2Radii.brMd,
      ),
      alignment: Alignment.center,
      child: UiV2Icon(UiV2Icons.folder, size: 24, color: t.textDim),
    );
  }
}

/// 开关（.switch）—— 52×30，选中态强调色，滑块 24
class UiV2Switch extends StatelessWidget {
  /// 是否打开
  final bool value;

  /// 切换回调
  final ValueChanged<bool>? onChanged;

  /// 无障碍标签
  final String semanticLabel;

  /// 构造开关
  const UiV2Switch({
    super.key,
    required this.value,
    this.onChanged,
    this.semanticLabel = '',
  });

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return Semantics(
      label: semanticLabel,
      toggled: value,
      child: UiV2Pressable(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        pressedScale: 1,
        child: AnimatedContainer(
          duration: UiV2Motion.d2,
          curve: UiV2Motion.enter,
          width: 52,
          height: 30,
          decoration: BoxDecoration(
            color: value ? t.accent : t.surface3,
            borderRadius: UiV2Radii.brPill,
          ),
          child: AnimatedAlign(
            duration: UiV2Motion.d2,
            curve: UiV2Motion.enter,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.all(3),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: value ? t.accentInk : t.text,
                borderRadius: UiV2Radii.brPill,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 统计卡（.stat + .stat--link）
class UiV2Stat extends StatelessWidget {
  /// 数字
  final String number;

  /// 说明
  final String caption;

  /// 点击回调（null 表示不可点）
  final VoidCallback? onTap;

  /// 构造统计卡
  const UiV2Stat({
    super.key,
    required this.number,
    required this.caption,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return UiV2Pressable(
      onTap: onTap,
      pressedScale: 1,
      child: Container(
        padding: const EdgeInsets.all(UiV2Spacing.s4),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.line),
          borderRadius: UiV2Radii.brLg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(number, style: UiV2Text.statNum.copyWith(color: t.text)),
            Text(caption, style: UiV2Text.hint.copyWith(color: t.textDim)),
          ],
        ),
      ),
    );
  }
}

/// 扫描状态框（.scan-status）
class UiV2ScanStatus extends StatelessWidget {
  /// 状态行：(语调, 图标, 文案)，语调取 ok / warn / plain
  final List<(String, String, String)> lines;

  /// 构造状态框
  const UiV2ScanStatus({super.key, required this.lines});

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: UiV2Spacing.s4,
        vertical: UiV2Spacing.s3,
      ),
      decoration: BoxDecoration(
        color: t.surface2,
        border: Border.all(color: t.line),
        borderRadius: UiV2Radii.brMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (tone, icon, text) in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: UiV2Icon(
                      icon,
                      size: 16,
                      color: switch (tone) {
                        'ok' => t.ok,
                        'warn' => t.warn,
                        _ => t.textDim,
                      },
                    ),
                  ),
                  const SizedBox(width: UiV2Spacing.s2),
                  Expanded(
                    child: Text(
                      text,
                      style: UiV2Text.buttonSmall.copyWith(
                        color: tone == 'ok' ? t.text : t.textDim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 睡眠定时器当前状态卡（.sleep-now）
class UiV2SleepNow extends StatelessWidget {
  /// 剩余时间文案（如 14:59）
  final String remain;

  /// 构造状态卡
  const UiV2SleepNow({super.key, required this.remain});

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: UiV2Spacing.s4),
      padding: const EdgeInsets.all(UiV2Spacing.s4),
      decoration: BoxDecoration(
        color: t.surface2,
        border: Border.all(color: t.line),
        borderRadius: UiV2Radii.brLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('剩余时间', style: UiV2Text.hint.copyWith(color: t.textDim)),
          Text(remain, style: UiV2Text.statNum.copyWith(color: t.text)),
          const SizedBox(height: UiV2Spacing.s2),
          Text(
            '到点后自动暂停播放；重新设定会覆盖当前倒计时。',
            style: UiV2Text.hint.copyWith(color: t.textDim),
          ),
        ],
      ),
    );
  }
}

/// 分类卡（.cat）：2/3/4 列的浏览分类方块
class UiV2CategoryCard extends StatelessWidget {
  /// 分类名
  final String name;

  /// 主色
  final Color color;

  /// 点击回调
  final VoidCallback? onTap;

  /// 构造分类卡
  const UiV2CategoryCard({
    super.key,
    required this.name,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return UiV2Pressable(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: UiV2Radii.brLg,
        child: Container(
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.all(UiV2Spacing.s4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color,
                Color.lerp(color, const Color(0xFF14171C), 0.45)!,
              ],
            ),
          ),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Text(
                  name,
                  style: UiV2Text.category.copyWith(color: const Color(0xFFFFFFFF)),
                ),
              ),
              Positioned(
                right: -20,
                bottom: -28,
                child: Transform.rotate(
                  angle: 24 * 3.1415926 / 180,
                  child: Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      color: const Color(0x29FFFFFF),
                      borderRadius: UiV2Radii.brLg,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分段分组标题（移动端筛选条 .filter-rail 用的横向滚动标签行）
class UiV2FilterRail extends StatelessWidget {
  /// 子项
  final List<Widget> children;

  /// 上边距
  final EdgeInsetsGeometry margin;

  /// 构造筛选条
  const UiV2FilterRail({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.only(
      top: UiV2Spacing.s4,
      bottom: UiV2Spacing.s5,
    ),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: UiV2Spacing.s2),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}
