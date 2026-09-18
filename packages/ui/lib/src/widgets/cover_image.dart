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

    // 按显示尺寸解码：列表 50、迷你条 40 的小图不再按原图（常 640+）进内存缓存
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheW = width != null && width!.isFinite
        ? (width! * dpr).round()
        : (height != null && height!.isFinite ? (height! * dpr).round() : null);

    return CachedNetworkImage(
      imageUrl: u,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: cacheW,
      // 列表快速滚动时骨架淡出拖沓：缩短淡入、去掉淡出
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: Duration.zero,
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
              size: (height ?? width ?? 48) * 0.45,
              color: cs.onSurfaceVariant),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: p,
    );
  }
}
