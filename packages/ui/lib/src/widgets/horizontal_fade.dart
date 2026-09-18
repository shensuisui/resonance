/// 横向滚动渐隐遮罩
///
/// 用于横向列表（最近播放 / 热门推荐等）右缘叠加"内容未结束"的视觉提示：
/// 右端由表面色渐隐到透明，提示可继续滑动。
/// 颜色用 Theme.colorScheme。
library;

import 'package:flutter/material.dart';

class HorizontalFade extends StatelessWidget {
  /// 遮罩宽度（默认 32）
  final double width;

  /// 遮罩色（一般取所在区域背景色）
  final Color color;

  const HorizontalFade({
    super.key,
    this.width = 32,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [color.withValues(alpha: 0), color],
            ),
          ),
        ),
      ),
    );
  }
}
