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
