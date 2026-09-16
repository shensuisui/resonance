/// 源执行日志总线 —— 应用级全局日志收集
///
/// 各音乐源/源管理器在执行搜索、获取播放地址、歌词等操作时埋点，
/// UI 通过 [stream] 订阅实时日志，或读取 [entries] 获取历史。
/// 环形缓冲保留最近 [_maxEntries] 条，避免无限增长。

import 'dart:async';

/// 日志级别
enum SourceLogLevel { info, warn, error }

/// 源执行日志条目
class SourceLogEntry {
  final DateTime time;

  /// 来源 id（如 fengye / 6uq / local_scan）
  final String sourceId;

  /// 日志级别（错误用于排障）
  final SourceLogLevel level;

  /// 操作类型：搜索 / 播放URL / 歌词 / 歌单 / 初始化 等
  final String action;

  /// 详情
  final String detail;

  const SourceLogEntry({
    required this.time,
    required this.sourceId,
    required this.level,
    required this.action,
    required this.detail,
  });

  /// 格式化时间（HH:mm:ss）
  String get timeText {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

/// 源执行日志总线
class SourceLogBus {
  /// 应用级共享实例
  static final SourceLogBus instance = SourceLogBus._();

  SourceLogBus._();

  static const int _maxEntries = 300;

  /// 控制台输出回调（可注入）
  ///
  /// 默认 null：仅在内存收集。壳工程注入后，日志同时打印到控制台，
  /// 便于排查插件失败（如 `(line) => debugPrint(line, wrapWidth: 0)`）。
  static void Function(String line)? consolePrinter;

  final StreamController<SourceLogEntry> _controller =
      StreamController<SourceLogEntry>.broadcast();
  final List<SourceLogEntry> _entries = [];

  /// 实时日志流
  Stream<SourceLogEntry> get stream => _controller.stream;

  /// 历史日志（最近 [_maxEntries] 条，新→旧）
  List<SourceLogEntry> get entries =>
      List.unmodifiable(_entries.reversed.toList());

  /// 记录一条日志（同时转发到控制台）
  void emit(
    String sourceId,
    SourceLogLevel level,
    String action,
    String detail,
  ) {
    final entry = SourceLogEntry(
      time: DateTime.now(),
      sourceId: sourceId,
      level: level,
      action: action,
      detail: detail,
    );
    _entries.add(entry);
    if (_entries.length > _maxEntries) {
      _entries.removeAt(0);
    }
    if (!_controller.isClosed) {
      _controller.add(entry);
    }
    // 控制台输出（可注入，见 consolePrinter）
    consolePrinter?.call(
      '[${entry.timeText}] [${entry.sourceId}] '
      '${entry.level.name.toUpperCase()} [${entry.action}] ${entry.detail}',
    );
  }

  /// 清空日志
  void clear() {
    _entries.clear();
  }

  /// 释放资源
  void dispose() {
    _controller.close();
  }
}