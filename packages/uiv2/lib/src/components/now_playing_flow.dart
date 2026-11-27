/// 沉浸播放页的展开/收起进度（点击、上滑、下滑共用同一进度，可撤回）
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/tokens.dart';

/// 播放页展开控制器：0=收起（播放条），1=全屏
class NowPlayingFlow extends ChangeNotifier {
  AnimationController? _controller;
  Rect? barRect;

  /// 是否正在拖拽（拖拽期间不要让外部布尔状态把进度弹回）
  bool dragging = false;

  double _dragStart = 0;
  double _dragOffset = 0;

  /// 挂载 ticker（由 Overlay 在 initState 调用）
  void attach(TickerProvider vsync) {
    _controller ??= AnimationController(vsync: vsync, duration: UiV2Motion.d3)
      ..addListener(notifyListeners);
  }

  /// 当前进度 0..1
  double get value => _controller?.value ?? 0;

  /// 是否已展开
  bool get isOpen => value > 0.5;

  /// 展开
  void open() {
    _controller?.animateTo(1, duration: UiV2Motion.d3, curve: UiV2Motion.enter);
  }

  /// 收起
  void close() {
    _controller?.animateTo(0, duration: UiV2Motion.d3, curve: UiV2Motion.exit);
  }

  /// 直接设置进度（仅供测试/复位）
  void setValue(double v) {
    _controller?.value = v.clamp(0.0, 1.0);
  }

  /// 拖拽开始
  void beginDrag() {
    _controller?.stop();
    dragging = true;
    _dragStart = value;
    _dragOffset = 0;
  }

  /// 拖拽更新：dy 为手指位移（向上为负），distance 为有效行程
  void dragBy(double dy, double distance) {
    if (_controller == null || distance <= 0) return;
    _dragOffset += dy;
    _controller!.value =
        (_dragStart + (-_dragOffset) / distance).clamp(0.0, 1.0);
  }

  /// 拖拽结束：返回是否展开
  ///
  /// 上滑快速轻扫（velocity < -600）也算展开；下滑快速（>600）收起。
  bool endDrag(double velocity) {
    dragging = false;
    final shouldOpen =
        velocity < -600 || (value > 0.5 && velocity <= 600);
    if (shouldOpen) {
      open();
    } else {
      close();
    }
    return shouldOpen;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}

/// 全局播放页 flow
final nowPlayingFlowProvider = Provider<NowPlayingFlow>((ref) {
  final flow = NowPlayingFlow();
  ref.onDispose(flow.dispose);
  return flow;
});
