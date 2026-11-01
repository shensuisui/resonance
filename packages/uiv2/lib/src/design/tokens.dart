/// 回响 Resonance 设计令牌 —— 与原型 assets/styles.css 的 CSS 变量一一对应。
///
/// 本文件是**唯一**的颜色/尺寸/动效来源：所有组件都从 [UiV2Tokens] 取值，
/// 禁止在组件里硬编码十六进制色值与魔法数字（见 AGENTS.md「配置/数据驱动」）。
///
/// 对应关系（原型 → Dart）：
///   --bg/--surface/--surface-2/--surface-3  → [UiV2Tokens.bg] 等
///   --s-1..--s-8                            → [UiV2Spacing]
///   --r-sm..--r-pill                        → [UiV2Radii]
///   --d-1..--d-4 / --e-enter / --e-exit     → [UiV2Motion]
library;

import 'package:flutter/widgets.dart';

/// 间距刻度（--s-1 … --s-8）。
abstract final class UiV2Spacing {
  /// 4px（--s-1）
  static const double s1 = 4;

  /// 8px（--s-2）
  static const double s2 = 8;

  /// 12px（--s-3）
  static const double s3 = 12;

  /// 16px（--s-4）
  static const double s4 = 16;

  /// 24px（--s-5）
  static const double s5 = 24;

  /// 32px（--s-6）
  static const double s6 = 32;

  /// 48px（--s-7）
  static const double s7 = 48;

  /// 64px（--s-8）
  static const double s8 = 64;
}

/// 圆角刻度（--r-sm … --r-pill）。
abstract final class UiV2Radii {
  /// 8px（--r-sm）
  static const Radius sm = Radius.circular(8);

  /// 12px（--r-md）
  static const Radius md = Radius.circular(12);

  /// 16px（--r-lg）
  static const Radius lg = Radius.circular(16);

  /// 20px（--r-xl）
  static const Radius xl = Radius.circular(20);

  /// 999px（--r-pill）
  static const Radius pill = Radius.circular(999);

  /// 8px 圆角边框
  static const BorderRadius brSm = BorderRadius.all(sm);

  /// 12px 圆角边框
  static const BorderRadius brMd = BorderRadius.all(md);

  /// 16px 圆角边框
  static const BorderRadius brLg = BorderRadius.all(lg);

  /// 20px 圆角边框
  static const BorderRadius brXl = BorderRadius.all(xl);

  /// 胶囊圆角边框
  static const BorderRadius brPill = BorderRadius.all(pill);
}

/// 动效令牌（原型 --d-1…--d-4 / --e-enter / --e-exit）。
abstract final class UiV2Motion {
  /// 150ms（--d-1）：hover/按压等即时反馈
  static const Duration d1 = Duration(milliseconds: 150);

  /// 220ms（--d-2）：展开、淡入
  static const Duration d2 = Duration(milliseconds: 220);

  /// 300ms（--d-3）：播放页/弹层位移
  static const Duration d3 = Duration(milliseconds: 300);

  /// 400ms（--d-4）
  static const Duration d4 = Duration(milliseconds: 400);

  /// cubic-bezier(.2,.7,.3,1)（--e-enter）
  static const Curve enter = Cubic(0.2, 0.7, 0.3, 1);

  /// cubic-bezier(.4,0,.7,.2)（--e-exit）
  static const Curve exit = Cubic(0.4, 0, 0.7, 0.2);
}

/// 响应式断点（原型 @media 查询）。
abstract final class UiV2Breakpoints {
  /// 768px：≥ 进入「宽屏」——侧栏出现、底部 Tab 隐藏、播放条一行三区。
  static const double wide = 768;

  /// 1024px：≥ 侧栏展开成完整宽度（品牌文字/导航文字/歌单分区回归）。
  static const double desktop = 1024;

  /// 1180px：≤ 视为平板——播放条隐藏歌名与音量组。
  static const double tabletMax = 1180;

  /// 1440px：≥ 加宽内容与卡片。
  static const double large = 1440;
}

/// 布局尺寸（原型 --sidebar-w / --rail-w / --player-min / --tabs-h / --content-max）。
abstract final class UiV2Metrics {
  /// 宽屏窄轨宽度 88px（--rail-w）
  static const double railWidth = 88;

  /// 桌面侧栏宽度 264px（--sidebar-w）
  static const double sidebarWidth = 264;

  /// 播放条最小高度 64px（--player-min）
  static const double playerBarHeight = 64;

  /// 底部 Tab 高度 60px（--tabs-h）
  static const double tabBarHeight = 60;

  /// 顶栏高度 56px
  static const double topBarHeight = 56;

  /// 内容最大宽度（--content-max）
  static const double contentMax = 1240;

  /// 1440px 以上的内容最大宽度
  static const double contentMaxLarge = 1280;

  /// 沉浸播放页内容最大宽度（.np__inner max-width）
  static const double nowPlayingMax = 1060;
}

/// 明暗两套配色令牌（对应 :root 与 [data-theme="light"]）。
@immutable
class UiV2Tokens {
  /// 页面底色（--bg）
  final Color bg;

  /// 一级表面（--surface）
  final Color surface;

  /// 二级表面（--surface-2）
  final Color surface2;

  /// 三级表面（--surface-3）
  final Color surface3;

  /// 描边（--line）
  final Color line;

  /// 强描边（--line-strong）
  final Color lineStrong;

  /// 主文字（--text）
  final Color text;

  /// 次级文字（--text-dim）
  final Color textDim;

  /// 三级文字（--text-mute）
  final Color textMute;

  /// 强调色（--accent）
  final Color accent;

  /// 强调色上的前景色（--accent-ink）
  final Color accentInk;

  /// 强调色淡底（--accent-soft）
  final Color accentSoft;

  /// 强调色更深的淡底，用于搜索命中高亮（--accent-soft-2）
  final Color accentSoft2;

  /// 成功色（--ok）
  final Color ok;

  /// 警告色（--warn）
  final Color warn;

  /// 危险色（--danger）
  final Color danger;

  /// 危险色淡底（--danger-soft）
  final Color dangerSoft;

  /// 遮罩（--scrim）
  final Color scrim;

  /// 浅遮罩（--scrim-2）
  final Color scrim2;

  /// 阴影 1（--shadow-1）
  final List<BoxShadow> shadow1;

  /// 阴影 2（--shadow-2）
  final List<BoxShadow> shadow2;

  /// 阴影 3（--shadow-3）
  final List<BoxShadow> shadow3;

  /// 是否暗色（决定沉浸播放页背景图不透明度等细节）
  final bool isDark;

  const UiV2Tokens({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.line,
    required this.lineStrong,
    required this.text,
    required this.textDim,
    required this.textMute,
    required this.accent,
    required this.accentInk,
    required this.accentSoft,
    required this.accentSoft2,
    required this.ok,
    required this.warn,
    required this.danger,
    required this.dangerSoft,
    required this.scrim,
    required this.scrim2,
    required this.shadow1,
    required this.shadow2,
    required this.shadow3,
    required this.isDark,
  });

  /// 暗色令牌（原型默认，:root）。
  static const UiV2Tokens dark = UiV2Tokens(
    bg: Color(0xFF0C0E11),
    surface: Color(0xFF14171C),
    surface2: Color(0xFF1C2027),
    surface3: Color(0xFF242A33),
    line: Color(0x14FFFFFF),
    lineStrong: Color(0x29FFFFFF),
    text: Color(0xFFF2F4F7),
    textDim: Color(0xFF9AA3AF),
    textMute: Color(0xFF79818D),
    accent: Color(0xFFFF5A3C),
    accentInk: Color(0xFF160804),
    accentSoft: Color(0x24FF5A3C),
    accentSoft2: Color(0x4DFF5A3C),
    ok: Color(0xFF3DD68C),
    warn: Color(0xFFF5C451),
    danger: Color(0xFFFF6B6B),
    dangerSoft: Color(0x29FF6B6B),
    scrim: Color(0xB8060709),
    scrim2: Color(0x80060709),
    shadow1: [BoxShadow(color: Color(0x47000000), blurRadius: 2, offset: Offset(0, 1))],
    shadow2: [BoxShadow(color: Color(0x57000000), blurRadius: 24, offset: Offset(0, 8))],
    shadow3: [BoxShadow(color: Color(0x80000000), blurRadius: 64, offset: Offset(0, 24))],
    isDark: true,
  );

  /// 亮色令牌（[data-theme="light"]）。
  static const UiV2Tokens light = UiV2Tokens(
    bg: Color(0xFFF6F7F9),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEEF0F4),
    surface3: Color(0xFFE2E6EC),
    line: Color(0x1A0C0E11),
    lineStrong: Color(0x330C0E11),
    text: Color(0xFF14171C),
    textDim: Color(0xFF5B626D),
    textMute: Color(0xFF6E7681),
    accent: Color(0xFFC9341C),
    accentInk: Color(0xFFFFFFFF),
    accentSoft: Color(0x1AC9341C),
    accentSoft2: Color(0x38C9341C),
    ok: Color(0xFF0F7A52),
    warn: Color(0xFF8A6200),
    danger: Color(0xFFC0362C),
    dangerSoft: Color(0x1FC0362C),
    scrim: Color(0x75161D1E),
    scrim2: Color(0x47161D1E),
    shadow1: [BoxShadow(color: Color(0x140C0E11), blurRadius: 2, offset: Offset(0, 1))],
    shadow2: [BoxShadow(color: Color(0x1A0C0E11), blurRadius: 24, offset: Offset(0, 8))],
    shadow3: [BoxShadow(color: Color(0x2E0C0E11), blurRadius: 64, offset: Offset(0, 24))],
    isDark: false,
  );

  /// 按解析出的亮度取对应令牌。
  static UiV2Tokens of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

/// 令牌作用域 —— 让子树通过 [UiV2Theme.of] 取到当前令牌。
///
/// 之所以不用 Material 的 ColorScheme：原型的语义槽位（surface-2/3、line、
/// scrim-2 等）与 M3 不是一一对应，强行映射会丢失精度。
class UiV2Theme extends InheritedWidget {
  /// 当前令牌
  final UiV2Tokens tokens;

  /// 构造令牌作用域
  const UiV2Theme({
    super.key,
    required this.tokens,
    required super.child,
  });

  /// 取当前令牌（无作用域时按系统亮度回退）。
  static UiV2Tokens of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<UiV2Theme>();
    if (scope != null) return scope.tokens;
    return UiV2Tokens.of(
      MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.dark,
    );
  }

  @override
  bool updateShouldNotify(UiV2Theme oldWidget) => tokens != oldWidget.tokens;
}
