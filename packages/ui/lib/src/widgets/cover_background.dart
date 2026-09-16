/// 封面主色渐变背景组件
///
/// 根据封面 URL 提取主色，渲染「主色(顶部透明叠加) → fallback(底部)」垂直渐变，
/// 用于播放页/迷你条/专辑页的沉浸式背景；无封面或提取失败回退 [fallback]。
/// 渐变颜色变化带 300ms 过渡动画。
/// 颜色用 Theme.colorScheme，间距用 AppSpacing。
library;

import 'package:flutter/material.dart';
import 'cover_palette.dart';

class CoverBackground extends StatefulWidget {
  /// 封面 URL（null/空 → 直接回退 [fallback]）
  final String? coverUrl;

  /// 无封面/提取失败时的回退色（一般取 Theme 表面色）
  final Color fallback;

  /// 渐变顶部主色透明度（0~1，越大主色越明显）
  final double topOpacity;

  final Widget child;

  const CoverBackground({
    super.key,
    required this.coverUrl,
    required this.fallback,
    this.topOpacity = 0.35,
    required this.child,
  });

  @override
  State<CoverBackground> createState() => _CoverBackgroundState();
}

class _CoverBackgroundState extends State<CoverBackground> {
  Color? _color;

  /// 当前请求中的封面 URL（防异步竞态：旧请求完成时不覆盖新状态）
  String? _requestingUrl;

  @override
  void initState() {
    super.initState();
    _load(widget.coverUrl);
  }

  @override
  void didUpdateWidget(covariant CoverBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverUrl != widget.coverUrl) {
      _load(widget.coverUrl);
    }
  }

  Future<void> _load(String? url) async {
    if (url == null || url.isEmpty) {
      _requestingUrl = null;
      if (_color != null) setState(() => _color = null);
      return;
    }
    _requestingUrl = url;
    final color = await CoverPalette.resolveColor(url);
    if (!mounted || _requestingUrl != url) return;
    setState(() => _color = color);
  }

  @override
  Widget build(BuildContext context) {
    final top = _color?.withValues(alpha: widget.topOpacity) ?? widget.fallback;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, widget.fallback],
        ),
      ),
      child: widget.child,
    );
  }
}
