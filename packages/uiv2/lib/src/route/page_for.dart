/// 按断点分派：移动端卡片推入，大屏淡入
library;

import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import 'card_page.dart';
import 'fade_page.dart';

/// 是否移动端形态
bool isMobileViewFor(BuildContext context) =>
    MediaQuery.sizeOf(context).width < UiV2Breakpoints.wide;

/// 按当前窗口宽度选择页面路由
Page<T> pageFor<T>({
  required BuildContext context,
  required Widget child,
  required LocalKey key,
  String? name,
}) {
  return isMobileViewFor(context)
      ? CardPage<T>(key: key, name: name, child: child)
      : FadePage<T>(key: key, name: name, child: child);
}
