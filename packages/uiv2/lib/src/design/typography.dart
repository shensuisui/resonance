/// 回响 Resonance 字体系统 —— 对应原型 --font-display / --font-body 与各级字号。
///
/// 字体文件随 App 打包（fm_app/assets/fonts/，见 fm_app/pubspec.yaml 的 fonts:）：
///   Manrope[wght].ttf / SpaceGrotesk[wght].ttf（可变字体，按 wght 轴取权重）
///
/// 原型字号表（styles.css 令牌）：
///   --fs-12/13/14/16/18/20/24/32/44/64，--lh-tight 1.2 / --lh-snug 1.35 / --lh-body 1.6
library;

import 'package:flutter/widgets.dart';

/// 正文字体族名（与 fm_app/pubspec.yaml 的声明一致）
const String kFontBody = 'Manrope';

/// 标题/品牌字体族名（Space Grotesk）
const String kFontDisplay = 'Space Grotesk';

/// 大标题字距 --tr-caps:.09em 的对应值（用于全大写小标签）
const double kTrackingCaps = 0.09;

/// 正文行高（--lh-body）
const double kLineHeightBody = 1.6;

/// 紧凑行高（--lh-tight）
const double kLineHeightTight = 1.2;

/// 回响的文本样式表 —— 每个字段都对应原型里一处具体文本。
abstract final class UiV2Text {
  static TextStyle _body({
    required double size,
    required FontWeight weight,
    double? height,
    Color? color,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: kFontBody,
        fontSize: size,
        fontWeight: weight,
        height: height,
        color: color,
        letterSpacing: letterSpacing,
      );

  static TextStyle _display({
    required double size,
    required FontWeight weight,
    double? height,
    Color? color,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: kFontDisplay,
        fontSize: size,
        fontWeight: weight,
        height: height,
        color: color,
        letterSpacing: letterSpacing,
      );

  /// 品牌名（.brand__name，display 20/700/1.1）
  static final TextStyle brandName =
      _display(size: 20, weight: FontWeight.w700, height: 1.1);

  /// 品牌副标（.brand__sub，10/400/.24em）
  static final TextStyle brandSub = _body(
    size: 10,
    weight: FontWeight.w400,
    letterSpacing: 0.24,
    height: 1.2,
  );

  /// 页面主标题（.page__title，display clamp(26,5vw,44) /600）
  static final TextStyle pageTitle =
      _display(size: 44, weight: FontWeight.w600, height: kLineHeightTight, letterSpacing: -0.44);

  /// 详情页英雄区标题（.hero__title，display clamp(28,7vw,44)）
  static final TextStyle heroTitle =
      _display(size: 44, weight: FontWeight.w600, height: kLineHeightTight, letterSpacing: -0.44);

  /// 区块标题（.section__title，display 20/600）
  static final TextStyle sectionTitle =
      _display(size: 20, weight: FontWeight.w600, height: kLineHeightTight, letterSpacing: -0.2);

  /// 沉浸播放页标题（.np__title，display clamp(20,5vw,24)）
  static final TextStyle npTitle =
      _display(size: 24, weight: FontWeight.w600, height: kLineHeightTight, letterSpacing: -0.24);

  /// 统计数字 / 计时数字（.stat__num、.sleep-now__time，display 24/700）
  static final TextStyle statNum =
      _display(size: 24, weight: FontWeight.w700, height: kLineHeightTight);

  /// 分类卡标题（.cat，display 18/700）
  static final TextStyle category = _display(size: 18, weight: FontWeight.w700, height: kLineHeightTight);

  /// 顶栏标题（.topbar__title，body 18/600）
  static final TextStyle topBarTitle = _body(size: 18, weight: FontWeight.w600, height: 1.3);

  /// 弹层标题（.sheet__title，display 18/600）
  static final TextStyle sheetTitle =
      _display(size: 18, weight: FontWeight.w600, height: kLineHeightTight);

  /// 空状态标题（.empty__title，display 18/600）
  static final TextStyle emptyTitle =
      _display(size: 18, weight: FontWeight.w600, height: kLineHeightTight);

  /// 曲名 / 列表主文本（.track__title、.card__name、.pb__title，14/600~700）
  static final TextStyle trackTitle = _body(size: 14, weight: FontWeight.w600, height: 1.3);

  /// 卡片名（.card__name，14/700）
  static final TextStyle cardName = _body(size: 14, weight: FontWeight.w700, height: 1.3);

  /// 行主文本（.list-row__label，14/600）
  static final TextStyle rowLabel = _body(size: 14, weight: FontWeight.w600, height: 1.3);

  /// 正文（body 16/400/1.6）
  static final TextStyle body = _body(size: 16, weight: FontWeight.w400, height: kLineHeightBody);

  /// 次级说明（.page__sub、.hero__meta、.empty__text，14/400/1.6）
  static final TextStyle bodyDim = _body(size: 14, weight: FontWeight.w400, height: kLineHeightBody);

  /// 行提示（.list-row__hint、.card__meta、.pick__sub，12/400）
  static final TextStyle hint = _body(size: 12, weight: FontWeight.w400, height: 1.4);

  /// 曲目副行艺人（.track__artist，12/400）
  static final TextStyle trackArtist = _body(size: 12, weight: FontWeight.w400, height: 1.4);

  /// 时长 / 序号（.track__dur、.track__idx，13/400 等宽数字）
  static final TextStyle duration = _body(size: 13, weight: FontWeight.w400, height: 1.3);

  /// 进度时间（.progress__time，11/400 等宽数字）
  static final TextStyle progressTime = _body(size: 11, weight: FontWeight.w400, height: 1.2);

  /// 徽标（.badge，11/700/.02em）
  static final TextStyle badge = _body(size: 11, weight: FontWeight.w700, height: 1.2, letterSpacing: 0.22);

  /// 底部 Tab 文案（.tab，11/600）
  static final TextStyle tabLabel = _body(size: 11, weight: FontWeight.w600, height: 1.2);

  /// 全大写分区标签（.sidebar__label、.np__ctx-line1、.hero__type，12/700/.09em）
  static final TextStyle capsLabel = _body(
    size: 12,
    weight: FontWeight.w700,
    letterSpacing: 0.09 * 12,
    height: 1.3,
  );

  /// 更小的全大写标签（11/700/.09em，如歌词提示行）
  static final TextStyle capsLabelSmall = _body(
    size: 11,
    weight: FontWeight.w700,
    letterSpacing: 0.09 * 11,
    height: 1.3,
  );

  /// 按钮文字（.btn，14/700）
  static final TextStyle button = _body(size: 14, weight: FontWeight.w700, height: 1.2);

  /// 次级按钮文字（.ghost-mini、.chip，13/600）
  static final TextStyle buttonSmall = _body(size: 13, weight: FontWeight.w600, height: 1.2);

  /// 动作行文字（.action-row，14/600）
  static final TextStyle actionRow = _body(size: 14, weight: FontWeight.w600, height: 1.3);

  /// 歌词行（.ly__line，clamp(17,4.4vw,20)/600/1.5）
  static final TextStyle lyrics = _body(size: 19, weight: FontWeight.w600, height: 1.5);
}
