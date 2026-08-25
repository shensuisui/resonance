/// 圆角静态值 —— 禁止魔法数字
///
/// 所有 BorderRadius / ClipRRect 统一引用此类。
class AppRadius {
  AppRadius._();

  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s24 = 24;

  /// 圆形（头像、播放按钮等）
  static const double full = 999;
}
