/// agent 调试层（Flan）的元素发现配置。
///
/// 三张表集中放这里，不散落在业务组件里：
///   * isInteractiveWidget —— 哪些**自定义**组件算可点/可输
///   * shouldStopTraversal —— 哪些子树不该继续下钻
///   * extractText         —— 自定义组件自带文本时从哪里取
///
/// 依据 flutter-agent-drive-app skill 第 5 章：内置已覆盖 Text/RichText/
/// EditableText/TextField/TextFormField，所以这里的 extractText 只处理 uiv2 自己的组件。
library;

import 'package:flan_flutter/flan_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:uiv2/uiv2.dart';

/// uiv2 里自定义的可点 / 可输叶子组件
bool _isInteractiveWidget(Type type) =>
    type == UiV2Pressable ||
    type == UiV2IconButton ||
    type == UiV2PlayButton ||
    type == UiV2Button ||
    type == UiV2GhostMini ||
    type == UiV2ListRow ||
    type == UiV2Segmented ||
    type == UiV2Switch ||
    type == UiV2Stat ||
    type == UiV2Chevron;

/// 需要停止遍历的子树
///
/// uiv2 目前没有 WebView / 相机预览这类"子树无交互元素"的重组件；
/// 封面是普通 Image，不能停（停了会丢掉同级的爱心/更多按钮）。
bool _shouldStopTraversal(Type type) => false;

/// 从自定义组件里取文本（内置 Text 已覆盖，这里只补 uiv2 自己的）
String? _extractText(Widget widget) {
  if (widget is UiV2ListRow) return widget.label;
  if (widget is UiV2Button) return widget.label;
  if (widget is UiV2GhostMini) return widget.label;
  if (widget is UiV2SongRow) return widget.song.title;
  return null;
}

/// 交给 FlanBinding 的配置
///
/// maxScreenshotSize 设 null：截图保持原始物理尺寸，布局巡检要看真像素，
/// 不接受 skill 里提到的"下采样后看不出 2px 溢出"。
FlanConfiguration agentDebugConfiguration() => FlanConfiguration(
      maxScreenshotSize: null,
      isInteractiveWidget: _isInteractiveWidget,
      shouldStopTraversal: _shouldStopTraversal,
      extractText: _extractText,
    );
