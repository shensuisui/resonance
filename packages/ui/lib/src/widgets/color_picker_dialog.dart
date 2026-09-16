/// HSV 取色器对话框 —— 设置页「主题色」自定义入口
///
/// 提供饱和度/明度二维色板 + 色相条，实时预览与 hex 展示。
/// 返回用户确认的颜色；取消返回 null。
/// 颜色用 Theme.colorScheme，间距用 AppSpacing，圆角用 AppRadius。
library;

import 'package:flutter/material.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radius.dart';
import '../theme/app_theme.dart';

/// 弹出取色器对话框，返回选中的颜色；取消返回 null。
Future<Color?> showColorPickerDialog(
  BuildContext context, {
  Color initial = kDefaultSeedColor,
}) {
  return showDialog<Color>(
    context: context,
    builder: (_) => ColorPickerDialog(initial: initial),
  );
}

/// 取色器对话框（HSV 模型）
class ColorPickerDialog extends StatefulWidget {
  final Color initial;

  const ColorPickerDialog({super.key, required this.initial});

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  Color get _color => _hsv.toColor();

  /// 饱和度/明度二维色板：横轴饱和度(左0→右1)，纵轴明度(上1→下0)
  Widget _buildSvPanel() {
    final hueColor = HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor();
    return SizedBox(
      height: 180,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return GestureDetector(
            onPanDown: (d) => _updateSv(d.localPosition, w, h),
            onPanUpdate: (d) => _updateSv(d.localPosition, w, h),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.s8),
              child: Stack(
                children: [
                  // 底层：白 → 当前色相（横轴饱和度）
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.white, hueColor],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                    ),
                  ),
                  // 上层：透明 → 黑（纵轴明度）
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.transparent, Colors.black],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                  // 指示圆点
                  Positioned(
                    left: _hsv.saturation * w - 7,
                    top: (1 - _hsv.value) * h - 7,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _color,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(color: Colors.black38, blurRadius: 2),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 色相条：横轴 0°~360°
  Widget _buildHueBar() {
    final colors = [
      for (var i = 0; i <= 6; i++)
        HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor(),
    ];
    return SizedBox(
      height: 24,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          return GestureDetector(
            onPanDown: (d) => _updateHue(d.localPosition.dx, w),
            onPanUpdate: (d) => _updateHue(d.localPosition.dx, w),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: colors),
                      borderRadius: BorderRadius.circular(AppRadius.s12),
                    ),
                  ),
                ),
                // 当前色相指示（白框游标）
                Positioned(
                  left: (_hsv.hue / 360 * w - 8).clamp(0.0, w - 16),
                  top: 0,
                  child: Container(
                    width: 16,
                    height: 24,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.s4),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _updateSv(Offset pos, double w, double h) {
    setState(() {
      _hsv = _hsv
          .withSaturation((pos.dx / w).clamp(0.0, 1.0))
          .withValue((1 - pos.dy / h).clamp(0.0, 1.0));
    });
  }

  void _updateHue(double dx, double w) {
    setState(() {
      _hsv = _hsv.withHue((dx / w * 360).clamp(0.0, 360.0));
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('自定义颜色'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSvPanel(),
          const SizedBox(height: AppSpacing.s12),
          _buildHueBar(),
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: [
              // 当前颜色预览
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _color,
                  borderRadius: BorderRadius.circular(AppRadius.s8),
                  border: Border.all(color: cs.outlineVariant),
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Text(
                colorToHex(_color),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Spacer(),
              Text(
                'HSV',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _color),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
