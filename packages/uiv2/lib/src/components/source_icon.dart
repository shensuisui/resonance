/// 源图标：支持 base64 / 远程图片 / 资源图；缺省用源名首字兜底
///
/// 项目没有引入 flutter_svg（体积考虑），所以 .svg 图标按「首字」兜底，
/// 不会出现白块。图标统一裁成小圆角方块，保证在列表里整齐。
library;

import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/network_image.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../providers/providers.dart';

/// 按源 id 渲染源图标（内部解析源）
class UiV2SourceIcon extends ConsumerWidget {
  /// 源 id（null/空时显示占位）
  final String? sourceId;

  /// 边长
  final double size;

  /// 构造
  const UiV2SourceIcon({super.key, required this.sourceId, this.size = 18});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = sourceId;
    final source = (id == null || id.isEmpty)
        ? null
        : ref.watch(sourceManagerProvider).getSource(id);
    return UiV2SourceIconView(source: source, size: size);
  }
}

/// 封面角标版：图标 + 半透明底片，保证在任何封面上都清晰
class UiV2SourceBadge extends ConsumerWidget {
  /// 源 id
  final String? sourceId;

  /// 图标边长（底片会自动留 3px 内边距）
  final double size;

  /// 构造
  const UiV2SourceBadge({super.key, required this.sourceId, this.size = 16});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(size <= 16 ? 6 : 8),
        border: Border.all(color: t.line.withValues(alpha: 0.6)),
      ),
      child: UiV2SourceIcon(sourceId: sourceId, size: size),
    );
  }
}

/// 封面角标·贴角版：纯图标 + 一圈极淡暗描边（**不留底片、不留间距**）
///
/// 与 [UiV2SourceBadge] 的分工：
///   * [UiV2SourceBadge]：底片 + 1px 边框 + 3px 内边距，用在卡片封面（要 8px 存在感）；
///   * 本组件：给「紧贴封面右下角」用 —— 图标 12px 直接贴角，靠一圈暗描边在花哨
///     封面上勾出轮廓。
///
/// 描边画在**图标自身外沿的 1px 内**（用 Stack 叠一层，不参与布局），
/// 所以图标仍是 0px 贴角；若改成给容器加 border/padding，图标会被推到 1~2px 之外。
class UiV2SourceEdge extends ConsumerWidget {
  /// 源 id
  final String? sourceId;

  /// 图标边长（描边画在其内侧，不额外占位）
  final double size;

  /// 构造贴角角标
  const UiV2SourceEdge({super.key, required this.sourceId, this.size = 12});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 与 UiV2SourceIconView 的裁角保持一致（<=16 用 4）
    final radius = BorderRadius.circular(size <= 16 ? 4 : 6);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(child: UiV2SourceIcon(sourceId: sourceId, size: size)),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                // 极淡暗描边：既压住花哨封面，又不喧宾夺主
                border: Border.all(
                  color: const Color(0xFF000000).withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 纯展示版（已经拿到 [MusicSource] 时用，避免重复解析）
class UiV2SourceIconView extends StatelessWidget {
  /// 源（null 时显示「?」）
  final MusicSource? source;

  /// 边长
  final double size;

  /// 构造
  const UiV2SourceIconView({super.key, required this.source, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final info = source?.sourceInfo;
    final icon = info?.iconUrl ?? '';
    final fallback = _letter(t, info?.name ?? '');
    final Widget child;
    if (icon.startsWith('data:image')) {
      child = _fromData(icon, fallback);
    } else if (icon.startsWith('http://') || icon.startsWith('https://')) {
      // 没有 svg 解码器：.svg 直接走首字兜底，避免留白
      child = icon.toLowerCase().contains('.svg')
          ? fallback
          : UiV2NetworkImage(url: icon, fit: BoxFit.cover, fallback: fallback);
    } else if (icon.startsWith('assets/')) {
      child = Image.asset(
        icon,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    } else {
      child = fallback;
    }
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size <= 16 ? 4 : 6),
        child: child,
      ),
    );
  }

  /// data:image/...;base64,xxx
  Widget _fromData(String data, Widget fallback) {
    final comma = data.indexOf(',');
    if (comma < 0) return fallback;
    try {
      return Image.memory(
        base64Decode(data.substring(comma + 1)),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    } catch (_) {
      return fallback;
    }
  }

  /// 首字兜底（中文取第一个字，英文取首字母）
  Widget _letter(UiV2Tokens t, String name) {
    final letter = name.isEmpty ? '?' : name.substring(0, 1);
    return ColoredBox(
      color: t.accentSoft,
      child: Center(
        child: Text(
          letter,
          style: UiV2Text.hint.copyWith(
            color: t.accent,
            fontSize: size * 0.62,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
