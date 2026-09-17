/// 统一封面图片组件 —— 缓存 + 骨架 + 占位（对标 PixelPlayer SmartImage）
///
/// 封装 cached_network_image（内存/磁盘缓存）：
/// - 加载中显示骨架屏微光（ShimmerBox）
/// - 失败/无 URL 回退默认音符占位（或自定义 [placeholder]）
/// - 圆角统一 [radius]
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_radius.dart';
import 'shimmer_box.dart';

class CoverImage extends StatelessWidget {
  /// 图片 URL（null/空 → 直接占位）
  final String? url;

  final double? width;
  final double? height;
  final BoxFit fit;

  /// 圆角（默认 8）
  final double radius;

  /// 自定义占位（默认音符图标容器）
  final Widget? placeholder;

  const CoverImage({
    super.key,
    this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.radius = AppRadius.s8,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.isEmpty) return _placeholder(context);

    return CachedNetworkImage(
      imageUrl: u,
      width: width,
      height: height,
      fit: fit,
      imageBuilder: (context, imageProvider) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image(
          image: imageProvider,
          width: width,
          height: height,
          fit: fit,
        ),
      ),
      placeholder: (context, _) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: ShimmerBox(width: width, height: height,
            radius: BorderRadius.circular(radius)),
      ),
      errorWidget: (context, _, _) => _placeholder(context),
    );
  }

  /// 默认占位：音符图标容器（圆角同封面）
  Widget _placeholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = placeholder ??
        Container(
          width: width,
          height: height,
          color: cs.surfaceContainerHighest,
          child: Icon(Icons.music_note_rounded,
              size: (height ?? 48) * 0.45, color: cs.onSurfaceVariant),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: p,
    );
  }
}
