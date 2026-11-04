import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/typography.dart';

/// 标记几何 —— 与 App 图标（resonance_app/assets/icon/app_icon.svg）**同一份**数据。
///
/// 全部是相对边长归一化的比例。改图形时两边要一起改；
/// packages/uiv2/test/app_icon_asset_test.dart 能校验 PNG 资产的颜色，
/// 但「图标里的形状」与「App 内的标记」是否一致只能靠这里的常量与 SVG 对齐。
class _Mark {
  /// 中心圆点相对边长的半径
  static const double dotR = 0.0993;

  /// 弧的半径（圆心到弧中线）
  static const double arcR = 0.235;

  /// 弧线宽
  static const double arcWidth = 0.088;

  /// 每道弧的张角（弧度）
  static const double sweep = math.pi * 0.44;

  // 注意：上面的比例都是「相对整块画布」的（与 App 图标一致，墨迹约占边长 56%）。
  // 不要再乘一个「标记占画布多少」的系数 —— 那等于把图形缩两遍
  // （0.558² ≈ 0.31，实测标记会小到只有 31%）。
}

/// 品牌标记 —— 圆点 + 左右各一道向外的弧（「回响 / 回声」）。
///
/// 为什么抽成组件，而不是继续用 [UiV2Icons.note]：
/// 旧标记是「音符图标 + 圆角方块」临时拼出来的，和 App 图标不是同一套图形，
/// 一旦换了 App 图标，两处就对不上（用户就是先看到侧栏还是旧音符才发现）。
/// 抽成组件后 App 内所有品牌标记都来自同一份几何，改图标只需改这里。
class UiV2BrandMark extends StatelessWidget {
  /// 外框边长（含圆角方块底色）
  final double size;

  /// 底色；不传用主题 accent
  final Color? background;

  /// 标记色；不传用主题 accentInk
  final Color? foreground;

  /// 外框圆角；不传用主题中号圆角
  final BorderRadius? radius;

  /// 构造品牌标记
  const UiV2BrandMark({
    super.key,
    this.size = 40,
    this.background,
    this.foreground,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? t.accent,
        borderRadius: radius ?? UiV2Radii.brMd,
      ),
      child: CustomPaint(
        painter: _BrandMarkPainter(color: foreground ?? t.accentInk),
        size: Size(size, size),
      ),
    );
  }
}

/// 品牌行 —— 标记 + 「回响 / RESONANCE」字标。
///
/// 单独抽出来是为了能直接测：侧栏 [UiV2Sidebar] 要拖一堆 provider，
/// 为了断言「这里用的不是旧音符」去 pump 整个侧栏，测试会又慢又脆。
class UiV2BrandRow extends StatelessWidget {
  /// 是否显示字标；侧栏收成窄轨时只留标记
  final bool showName;

  /// 标记边长
  final double markSize;

  /// 构造品牌行
  const UiV2BrandRow({super.key, this.showName = true, this.markSize = 40});

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        UiV2BrandMark(size: markSize),
        if (showName) ...[
          const SizedBox(width: UiV2Spacing.s3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('回响', style: UiV2Text.brandName.copyWith(color: t.text)),
              Text(
                'RESONANCE',
                style: UiV2Text.brandSub.copyWith(color: t.textMute),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  final Color color;
  const _BrandMarkPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // shortestSide 保证非正方形容器里也按整数边长画
    final side = size.shortestSide;
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = _Mark.arcWidth * side;

    canvas.save();
    // 直接按整块画布的归一化坐标画：与 App 图标里标记的位置完全一致（居中略偏下 0.52）
    final center = Offset(0.5 * side, 0.52 * side);
    canvas.drawCircle(center, _Mark.dotR * side, fill);
    final ring = Rect.fromCircle(center: center, radius: _Mark.arcR * side);
    canvas.drawArc(ring, -_Mark.sweep / 2, _Mark.sweep, false, stroke);
    canvas.drawArc(
      ring,
      math.pi - _Mark.sweep / 2,
      _Mark.sweep,
      false,
      stroke,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandMarkPainter old) => old.color != color;
}
