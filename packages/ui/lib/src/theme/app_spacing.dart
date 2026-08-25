/// 间距静态值 —— 禁止魔法数字
///
/// 所有 padding / margin / SizedBox / gap 统一引用此类，
/// 确保全应用间距一致且可全局调整。
class AppSpacing {
  AppSpacing._();

  static const double s2 = 2;
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s48 = 48;
  static const double s64 = 64;
}
