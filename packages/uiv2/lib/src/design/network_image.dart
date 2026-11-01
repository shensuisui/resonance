/// 网络图片统一入口：请求头 + 磁盘缓存
///
/// 为什么不用裸 Image.network：它只有 Flutter 的内存 ImageCache（进程退出即失效），
/// 远端源封面每次启动都要重下；而且枫叶这类 CDN 校验 referer，裸请求会 403。
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'icons.dart';
import 'tokens.dart';

/// 图片缓存策略（集中一处，不把天数/数量散落在调用点）
class UiV2ImageCachePolicy {
  /// 缓存有效期（天）
  final int maxAgeDays;

  /// 最多缓存多少个对象
  final int maxObjects;

  /// 磁盘缓存键名（换策略时换 key 可避免复用旧目录）
  final String cacheKey;

  /// 构造
  const UiV2ImageCachePolicy({
    this.maxAgeDays = 30,
    this.maxObjects = 300,
    this.cacheKey = 'uiv2_images',
  });
}

/// 默认策略
const UiV2ImageCachePolicy kUiV2ImageCachePolicy = UiV2ImageCachePolicy();

UiV2ImageCachePolicy _policy = kUiV2ImageCachePolicy;
CacheManager? _manager;

/// 配置缓存策略（App 启动时调一次；已建的管理器会重建）
void configureUiV2ImageCache(
    [UiV2ImageCachePolicy policy = kUiV2ImageCachePolicy]) {
  _policy = policy;
  _manager = null;
}

/// 当前缓存管理器
CacheManager get uiV2ImageCacheManager => _manager ??= CacheManager(Config(
      _policy.cacheKey,
      stalePeriod: Duration(days: _policy.maxAgeDays),
      maxNrOfCacheObjects: _policy.maxObjects,
    ));

/// 清空磁盘缓存与内存缓存（设置页「清理图片缓存」用）
Future<void> clearUiV2ImageCache() async {
  await uiV2ImageCacheManager.emptyCache();
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
}

/// 统一的网络图片组件：带请求头、磁盘缓存、占位与失败兜底
class UiV2NetworkImage extends StatelessWidget {
  /// 图片地址
  final String url;

  /// 请求头（源的 referer 等）
  final Map<String, String> headers;

  /// 填充方式
  final BoxFit fit;

  /// 失败兜底（默认灰底 + 音符图标）
  final Widget? fallback;

  /// 构造
  const UiV2NetworkImage({
    super.key,
    required this.url,
    this.headers = const <String, String>{},
    this.fit = BoxFit.cover,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: headers,
      cacheManager: uiV2ImageCacheManager,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (_, __) => Container(color: t.surface3),
      errorWidget: (_, __, ___) =>
          fallback ??
          Container(
            color: t.surface3,
            alignment: Alignment.center,
            child: UiV2Icon(UiV2Icons.note, size: 22, color: t.textMute),
          ),
    );
  }
}
