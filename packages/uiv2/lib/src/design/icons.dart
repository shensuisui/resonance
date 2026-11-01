/// 回响 Resonance 图标集 —— 与原型 index.html 内联 SVG sprite（#i-*）逐条对齐。
///
/// 原型把 24×24 的图标放在 <symbol> 里，用 currentColor 描边或填充。
/// 这里用等价的 Flutter 形状重建（同尺寸、同线宽、同端点样式），
/// 不引入图标字体或第三方图标包，保证与原型观感一致。
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// 一个图标的绘制指令：一段路径 + 该段的绘制模式。
@immutable
class _Op {
  /// SVG path 的 d 属性（24×24 坐标系）
  final String d;

  /// true 表示填充，false 表示描边
  final bool fill;

  const _Op(this.d, {this.fill = false});
}

/// 图标目录：名字 → 绘制指令。
///
/// 键名与原型 sprite 的 `#i-<name>` 一致，便于与 HTML 对照维护。
const Map<String, List<_Op>> _catalog = {
  'home': [
    _Op('M3 10.6 12 3l9 7.6'),
    _Op('M5.2 9.4V20a1 1 0 0 0 1 1h11.6a1 1 0 0 0 1-1V9.4'),
    _Op('M9.6 21v-6.2h4.8V21'),
  ],
  'search': [
    _Op('M17.6 11a6.6 6.6 0 1 1-13.2 0 6.6 6.6 0 0 1 13.2 0z'),
    _Op('m20 20-3.6-3.6'),
  ],
  'library': [
    _Op('m12 3.4 8.6 4.6L12 12.6 3.4 8z'),
    _Op('m3.4 13.2 8.6 4.6 8.6-4.6'),
  ],
  'user': [
    _Op('M15.6 8.2a3.6 3.6 0 1 1-7.2 0 3.6 3.6 0 0 1 7.2 0z'),
    _Op('M5 20.2c0-3.4 3.1-5.8 7-5.8s7 2.4 7 5.8'),
  ],
  'play': [
    _Op('M8 5.2v13.6L19 12z', fill: true),
  ],
  'pause': [
    _Op('M8.2 5h1a1.2 1.2 0 0 1 1.2 1.2v11.6A1.2 1.2 0 0 1 9.2 19h-1A1.2 1.2 0 0 1 7 17.8V6.2A1.2 1.2 0 0 1 8.2 5z', fill: true),
    _Op('M14.8 5h1A1.2 1.2 0 0 1 17 6.2v11.6A1.2 1.2 0 0 1 15.8 19h-1A1.2 1.2 0 0 1 13.6 17.8V6.2A1.2 1.2 0 0 1 14.8 5z', fill: true),
  ],
  'prev': [
    _Op('M6.1 5.4v13.2'),
    _Op('M6.8 12 17.6 5.3v13.4z', fill: true),
  ],
  'next': [
    _Op('M17.9 5.4v13.2'),
    _Op('M17.2 12 6.4 5.3v13.4z', fill: true),
  ],
  'shuffle': [
    _Op('M19 16.5 22 20l-3 3.5', fill: true),
    _Op('M19 0.5 22 4l-3 3.5', fill: true),
    _Op('M2 18h1.97a4 4 0 0 0 3.3-1.7l5.46-8.6a4 4 0 0 1 3.3-1.7H22'),
    _Op('M2 6h1.97a4 4 0 0 1 3.6 2.2'),
    _Op('M22 18h-6.04a4 4 0 0 1-3.3-1.8l-.36-.45'),
  ],
  'repeat': [
    _Op('m14.6 1.7 3.5 3.5-3.5 3.5'),
    _Op('M3 11v-1a4 4 0 0 1 4-4h10.4'),
    _Op('m9.4 22.3-3.5-3.5 3.5-3.5'),
    _Op('M21 13v1a4 4 0 0 1-4 4H6.6'),
  ],
  'repeatOne': [
    _Op('m14.6 1.7 3.5 3.5-3.5 3.5'),
    _Op('M3 11v-1a4 4 0 0 1 4-4h10.4'),
    _Op('m9.4 22.3-3.5-3.5 3.5-3.5'),
    _Op('M21 13v1a4 4 0 0 1-4 4H6.6'),
    _Op('M11.5 10h1v4'),
  ],
  'heart': [
    _Op('M12 20.4 4.6 13a4.7 4.7 0 0 1 6.6-6.7l.8.8.8-.8A4.7 4.7 0 0 1 19.4 13z'),
  ],
  'heartFill': [
    _Op('M12 20.4 4.6 13a4.7 4.7 0 0 1 6.6-6.7l.8.8.8-.8A4.7 4.7 0 0 1 19.4 13z', fill: true),
  ],
  'chevronDown': [_Op('m6 9.5 6 6 6-6')],
  'chevronRight': [_Op('m9.5 6 6 6-6 6')],
  'expand': [_Op('m6 14.5 6-6 6 6')],
  'arrowLeft': [
    _Op('M20 12H4'),
    _Op('m11 19-7-7 7-7'),
  ],
  'more': [
    _Op('M6.6 12a1.6 1.6 0 1 1-3.2 0 1.6 1.6 0 0 1 3.2 0z', fill: true),
    _Op('M13.6 12a1.6 1.6 0 1 1-3.2 0 1.6 1.6 0 0 1 3.2 0z', fill: true),
    _Op('M20.6 12a1.6 1.6 0 1 1-3.2 0 1.6 1.6 0 0 1 3.2 0z', fill: true),
  ],
  'edit': [
    _Op('M4 20h4L18.4 9.6a2.8 2.8 0 1 0-4-4L4 16v4Z'),
    _Op('m14.5 6.5 3.5 3.5'),
  ],
  'trash': [
    _Op('M4 7h16'),
    _Op('M9.5 4h5'),
    _Op('M6.5 7l.9 11.2A2 2 0 0 0 9.4 20h5.2a2 2 0 0 0 2-1.8L17.5 7'),
    _Op('M10.5 11v5.5M13.5 11v5.5'),
  ],
  'queue': [
    _Op('M4 6h10'),
    _Op('M4 12h10'),
    _Op('M4 18h6'),
    _Op('M17 9v10'),
    _Op('m13.5 15.5 3.5 3.5 3.5-3.5'),
  ],
  'lyrics': [
    _Op('M6.6 3.4h10.8a1.8 1.8 0 0 1 1.8 1.8v13.6a1.8 1.8 0 0 1-1.8 1.8H6.6a1.8 1.8 0 0 1-1.8-1.8V5.2a1.8 1.8 0 0 1 1.8-1.8Z'),
    _Op('M8.8 8.8h6.4'),
    _Op('M8.8 12.2h6.4'),
    _Op('M8.8 15.6h4'),
  ],
  'volume': [
    _Op('M11 5.2 6.6 9H3.2v6h3.4L11 18.8z'),
    _Op('M15.2 9.4a3.6 3.6 0 0 1 0 5.2'),
    _Op('M18 6.6a7.4 7.4 0 0 1 0 10.8'),
  ],
  'volumeMute': [
    _Op('M11 5.2 6.6 9H3.2v6h3.4L11 18.8z'),
    _Op('m16 9.5 5 5'),
    _Op('m21 9.5-5 5'),
  ],
  'plus': [
    _Op('M12 5v14'),
    _Op('M5 12h14'),
  ],
  'download': [
    _Op('M12 4v11'),
    _Op('m7.5 11.5 4.5 4.5 4.5-4.5'),
    _Op('M5 20h14'),
  ],
  'check': [_Op('m5 12.8 4.6 4.6L19 7')],
  'close': [
    _Op('m6 6 12 12'),
    _Op('m18 6-12 12'),
  ],
  'folder': [
    _Op('M3.2 7.2a2 2 0 0 1 2-2h3.4l2 2.6h8.2a2 2 0 0 1 2 2v7.4a2 2 0 0 1-2 2H5.2a2 2 0 0 1-2-2z'),
  ],
  'globe': [
    _Op('M20.6 12a8.6 8.6 0 1 1-17.2 0 8.6 8.6 0 0 1 17.2 0z'),
    _Op('M3.4 12h17.2'),
    _Op('M12 3.4c2.5 2.4 3.8 5.4 3.8 8.6S14.5 18.2 12 20.6c-2.5-2.4-3.8-5.4-3.8-8.6S9.5 5.8 12 3.4z'),
  ],
  'clock': [
    _Op('M20.6 12a8.6 8.6 0 1 1-17.2 0 8.6 8.6 0 0 1 17.2 0z'),
    _Op('M12 7.4V12l3.2 2'),
  ],
  'note': [
    _Op('M9 18.2V6l10-2v11.4'),
    _Op('M9 18.2a2.6 2.6 0 1 1-5.2 0 2.6 2.6 0 0 1 5.2 0z'),
    _Op('M19 15.4a2.6 2.6 0 1 1-5.2 0 2.6 2.6 0 0 1 5.2 0z'),
  ],
  'disc': [
    _Op('M20.6 12a8.6 8.6 0 1 1-17.2 0 8.6 8.6 0 0 1 17.2 0z'),
    _Op('M14.6 12a2.6 2.6 0 1 1-5.2 0 2.6 2.6 0 0 1 5.2 0z'),
  ],
  'share': [
    _Op('M12 15.6V4'),
    _Op('m8 8 4-4 4 4'),
    _Op('M5 13.5V19h14v-5.5'),
  ],
  'info': [
    _Op('M20.6 12a8.6 8.6 0 1 1-17.2 0 8.6 8.6 0 0 1 17.2 0z'),
    _Op('M12 11v5.4'),
    _Op('M13.1 7.8a1.1 1.1 0 1 1-2.2 0 1.1 1.1 0 0 1 2.2 0z', fill: true),
  ],
  'device': [
    _Op('M15.3 5.7v12.6a2.2 2.2 0 0 1-2.2 2.2H10.9a2.2 2.2 0 0 1-2.2-2.2V5.7A2.2 2.2 0 0 1 10.9 3.5h2.2a2.2 2.2 0 0 1 2.2 2.2z'),
    _Op('M15 15.5a3 3 0 1 1-6 0 3 3 0 0 1 6 0z'),
    _Op('M13.1 7a1.1 1.1 0 1 1-2.2 0 1.1 1.1 0 0 1 2.2 0z', fill: true),
  ],
  'sun': [
    _Op('M16.2 12a4.2 4.2 0 1 1-8.4 0 4.2 4.2 0 0 1 8.4 0z'),
    _Op('M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2'),
    _Op('m5.2 5.2 1.4 1.4M17.4 17.4l1.4 1.4M18.8 5.2l-1.4 1.4M6.6 17.4l-1.4 1.4'),
  ],
  'moon': [
    _Op('M20.5 14.3A8.6 8.6 0 0 1 9.7 3.5a8.6 8.6 0 1 0 10.8 10.8z'),
  ],
};

/// 已解析的图标形状（惰性构建并按需缓存）。
class _ResolvedIcon {
  final Path stroked;
  final Path filled;
  const _ResolvedIcon(this.stroked, this.filled);
}

final Map<String, _ResolvedIcon> _resolved = {};

/// 解析 d 属性为 [Path]（SVG 路径语法的子集：M/L/H/V/C/A/Z 及其相对形式）。
Path _parseSvgPath(String d) {
  final path = Path();
  var i = 0;
  var cx = 0.0;
  var cy = 0.0;
  var startX = 0.0;
  var startY = 0.0;
  var prevCtrlX = 0.0;
  var prevCtrlY = 0.0;
  var command = '';
  var lastCommand = '';

  /// 读取一个数字。
  ///
  /// 严格按 SVG number 语法消费：[符号] 数字* ('.' 数字*)? ([eE] [符号] 数字+)?
  /// —— 「最多一个小数点」必须显式保证：像 heart 图标的 `l.8.8.8-.8` 里
  /// 连续的三个小数位，若贪心地把 `8 .8` 和 `.8.8` 吞成一个 token，
  /// double.parse 就会抛 FormatException 把整个界面打挂（历史故障）。
  ///
  /// 读不出合法数字时返回 0 且**不推进游标**，由调用方保证至少前进一个字符，
  /// 这样即使路径里有非法 token，最坏也只是这一个图标画得不完整。
  double readNumber() {
    while (i < d.length && (d[i] == ' ' || d[i] == ',' || d[i] == '\n')) {
      i++;
    }
    final start = i;
    if (i < d.length && (d[i] == '-' || d[i] == '+')) i++;
    while (i < d.length && d[i].codeUnitAt(0) >= 48 && d[i].codeUnitAt(0) <= 57) {
      i++;
    }
    if (i < d.length && d[i] == '.') {
      i++;
      while (i < d.length && d[i].codeUnitAt(0) >= 48 && d[i].codeUnitAt(0) <= 57) {
        i++;
      }
    }
    // 科学计数法（SVG 允许），但要求指数位至少有一位数字
    if (i < d.length && (d[i] == 'e' || d[i] == 'E')) {
      final expStart = i;
      i++;
      if (i < d.length && (d[i] == '-' || d[i] == '+')) i++;
      final digitsStart = i;
      while (i < d.length && d[i].codeUnitAt(0) >= 48 && d[i].codeUnitAt(0) <= 57) {
        i++;
      }
      if (i == digitsStart) i = expStart; // 指数不合法则退回，不吞掉 e
    }
    if (i == start) return 0; // 无任何可解析内容
    final slice = d.substring(start, i);
    final value = double.tryParse(slice);
    if (value == null) {
      i = start; // 让调用方按「非法 token」处理并前进
      return 0;
    }
    return value;
  }

  /// 安全读一个数字：**保证调用返回后游标一定前进**。
  ///
  /// 这是整个解析循环收敛的关键：只要每次迭代都在推进，就永远不可能死循环。
  /// 走到字符串末尾后（i == d.length）无法前进，按契约把游标退回一位，
  /// 让外层循环的下界条件 i < d.length 立即结束解析。
  double readSafe() {
    final before = i;
    final value = readNumber();
    if (i == before) {
      if (i < d.length) {
        i++;
      } else if (i > 0) {
        i--;
      }
    }
    return value;
  }

  bool isCommand(int c) {
    return (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
  }

  // 迭代上界：任何一条 24×24 图标路径的指令数都远小于这个值。
  // 万一还有没覆盖到的语法分支，宁可这个图标画残缺，也不能让主 isolate 卡死。
  var guard = 0;
  while (i < d.length) {
    if (++guard > 4096) break;
    final ch = d[i];
    if (ch == ' ' || ch == ',' || ch == '\n') {
      i++;
      continue;
    }
    if (isCommand(ch.codeUnitAt(0))) {
      command = ch;
      i++;
    } else {
      // 隐式重复上一个命令（M 后面的坐标对按 L 处理）
      command = command == 'M' ? 'L' : (command == 'm' ? 'l' : command);
      if (command.isEmpty) {
        i++;
        continue;
      }
    }

    switch (command) {
      case 'M':
        cx = readSafe();
        cy = readSafe();
        path.moveTo(cx, cy);
        startX = cx;
        startY = cy;
        lastCommand = 'M';
        break;
      case 'm':
        cx += readSafe();
        cy += readSafe();
        path.moveTo(cx, cy);
        startX = cx;
        startY = cy;
        lastCommand = 'm';
        break;
      case 'L':
        cx = readSafe();
        cy = readSafe();
        path.lineTo(cx, cy);
        lastCommand = 'L';
        break;
      case 'l':
        cx += readSafe();
        cy += readSafe();
        path.lineTo(cx, cy);
        lastCommand = 'l';
        break;
      case 'H':
        cx = readSafe();
        path.lineTo(cx, cy);
        lastCommand = 'H';
        break;
      case 'h':
        cx += readSafe();
        path.lineTo(cx, cy);
        lastCommand = 'h';
        break;
      case 'V':
        cy = readSafe();
        path.lineTo(cx, cy);
        lastCommand = 'V';
        break;
      case 'v':
        cy += readSafe();
        path.lineTo(cx, cy);
        lastCommand = 'v';
        break;
      case 'C':
        final x1 = readSafe();
        final y1 = readSafe();
        final x2 = readSafe();
        final y2 = readSafe();
        cx = readSafe();
        cy = readSafe();
        path.cubicTo(x1, y1, x2, y2, cx, cy);
        prevCtrlX = x2;
        prevCtrlY = y2;
        lastCommand = 'C';
        break;
      case 'c':
        final x1 = cx + readSafe();
        final y1 = cy + readSafe();
        final x2 = cx + readSafe();
        final y2 = cy + readSafe();
        cx += readSafe();
        cy += readSafe();
        path.cubicTo(x1, y1, x2, y2, cx, cy);
        prevCtrlX = x2;
        prevCtrlY = y2;
        lastCommand = 'c';
        break;
      case 'S':
        final x2 = readSafe();
        final y2 = readSafe();
        final nx = readSafe();
        final ny = readSafe();
        final reflect = (lastCommand == 'C' || lastCommand == 'c' || lastCommand == 'S' || lastCommand == 's');
        final x1 = reflect ? 2 * cx - prevCtrlX : cx;
        final y1 = reflect ? 2 * cy - prevCtrlY : cy;
        path.cubicTo(x1, y1, x2, y2, nx, ny);
        prevCtrlX = x2;
        prevCtrlY = y2;
        cx = nx;
        cy = ny;
        lastCommand = 'S';
        break;
      case 's':
        // 相对平滑三次曲线：只跟 4 个数字（x2 y2 x y），首控制点由上一段的
        // 控制点关于当前点镜像得到。历史上漏了这个分支，导致 's' 落进
        // 「隐式重复上一个命令」，多读两个数字后游标越过字符串末尾而**死循环**。
        {
          final x2 = cx + readSafe();
          final y2 = cy + readSafe();
          final nx = cx + readSafe();
          final ny = cy + readSafe();
          final reflect =
              (lastCommand == 'C' || lastCommand == 'c' || lastCommand == 'S' || lastCommand == 's');
          final x1 = reflect ? 2 * cx - prevCtrlX : cx;
          final y1 = reflect ? 2 * cy - prevCtrlY : cy;
          path.cubicTo(x1, y1, x2, y2, nx, ny);
          prevCtrlX = x2;
          prevCtrlY = y2;
          cx = nx;
          cy = ny;
          lastCommand = 's';
        }
        break;
      case 'A':
      case 'a':
        final rx = readSafe().abs();
        final ry = readSafe().abs();
        readSafe(); // x-axis-rotation（本图标集里均为 0）
        readSafe(); // large-arc-flag
        final sweep = readSafe() != 0;
        var ex = readSafe();
        var ey = readSafe();
        if (command == 'a') {
          ex += cx;
          ey += cy;
        }
        _appendArc(path, cx, cy, rx, ry, sweep, ex, ey);
        cx = ex;
        cy = ey;
        lastCommand = command;
        break;
      case 'Z':
      case 'z':
        path.close();
        cx = startX;
        cy = startY;
        lastCommand = command;
        break;
      default:
        break;
    }
  }
  return path;
}

/// 把 SVG 的 A 命令（椭圆弧）追加进 [path]。
///
/// 本图标集里的圆弧都是「半径相等、rotation=0」的圆弧，
/// 用 [Path.arcToPoint] 即可精确还原。
void _appendArc(
  Path path,
  double sx,
  double sy,
  double rx,
  double ry,
  bool sweep,
  double ex,
  double ey,
) {
  final dx = (sx - ex) / 2;
  final dy = (sy - ey) / 2;
  final dist = math.sqrt(dx * dx + dy * dy);
  var radius = rx;
  if (dist > radius) {
    // 端点距离超过直径：按 SVG 规范放大半径到刚好够用
    radius = dist;
  }
  path.arcToPoint(
    Offset(ex, ey),
    radius: Radius.circular(radius),
    clockwise: sweep,
  );
}

_ResolvedIcon _resolve(String name) {
  final cached = _resolved[name];
  if (cached != null) return cached;
  final ops = _catalog[name];
  final stroked = Path();
  final filled = Path();
  if (ops != null) {
    for (final op in ops) {
      final p = _parseSvgPath(op.d);
      if (op.fill) {
        filled.addPath(p, Offset.zero);
      } else {
        stroked.addPath(p, Offset.zero);
      }
    }
  }
  final result = _ResolvedIcon(stroked, filled);
  _resolved[name] = result;
  return result;
}

/// 回响图标 —— 线性图标以 currentColor 描边，填充图标同色填充。
///
/// 用法：`UiV2Icon(UiV2Icons.play, size: 22, color: tokens.text)`
class UiV2Icon extends StatelessWidget {
  /// 图标名（见 [UiV2Icons]）
  final String name;

  /// 绘制尺寸（默认 22，同原型 .ic）
  final double size;

  /// 颜色（默认继承最近的 [IconTheme]，否则用当前文本色）
  final Color? color;

  /// 构造图标
  const UiV2Icon(this.name, {super.key, this.size = 22, this.color});

  @override
  Widget build(BuildContext context) {
    final resolved = _resolve(name);
    final painter = _UiV2IconPainter(
      resolved: resolved,
      color: color ?? IconTheme.of(context).color ?? const Color(0xFFF2F4F7),
    );
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: painter,
        size: Size(size, size),
        isComplex: false,
      ),
    );
  }
}

/// 图标名常量（与原型 sprite 的 #i-<name> 对应）。
abstract final class UiV2Icons {
  static const String home = 'home';
  static const String search = 'search';
  static const String library = 'library';
  static const String user = 'user';
  static const String play = 'play';
  static const String pause = 'pause';
  static const String prev = 'prev';
  static const String next = 'next';
  static const String shuffle = 'shuffle';
  static const String repeat = 'repeat';
  static const String repeatOne = 'repeatOne';
  static const String heart = 'heart';
  static const String heartFill = 'heartFill';
  static const String chevronDown = 'chevronDown';
  static const String chevronRight = 'chevronRight';
  static const String expand = 'expand';
  static const String arrowLeft = 'arrowLeft';
  static const String more = 'more';
  static const String edit = 'edit';
  static const String trash = 'trash';
  static const String queue = 'queue';
  static const String lyrics = 'lyrics';
  static const String volume = 'volume';
  static const String volumeMute = 'volumeMute';
  static const String plus = 'plus';
  static const String download = 'download';
  static const String check = 'check';
  static const String close = 'close';
  static const String folder = 'folder';
  static const String globe = 'globe';
  static const String clock = 'clock';
  static const String note = 'note';
  static const String disc = 'disc';
  static const String share = 'share';
  static const String info = 'info';
  static const String device = 'device';
  static const String sun = 'sun';
  static const String moon = 'moon';
}

/// 图标画笔：把 24×24 的形状缩放到目标尺寸后按 1.75 线宽描边（同原型）。
class _UiV2IconPainter extends CustomPainter {
  final _ResolvedIcon resolved;
  final Color color;

  const _UiV2IconPainter({required this.resolved, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.save();
    canvas.scale(scale, scale);
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    if (resolved.filled.getBounds().isEmpty == false) {
      canvas.drawPath(resolved.filled, fillPaint);
    }
    if (resolved.stroked.getBounds().isEmpty == false) {
      canvas.drawPath(resolved.stroked, strokePaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_UiV2IconPainter oldDelegate) =>
      oldDelegate.color != color || !identical(oldDelegate.resolved, resolved);
}

/// 把 [Path] 转成 [ui.Path]（仅供需要路径度量的场景使用）。
ui.Path debugParseIconPath(String d) => _parseSvgPath(d);
