/// 数据库写变更总线（纯 Dart，无平台依赖）
///
/// 目的：让「同步层」感知「本机数据变了」，从而按防抖策略触发推送，
/// 而不是轮询/定时全表比对。
///
/// 分工：
///   * [DbChangeBus] 只管广播；谁写库谁 `emit`；
///   * [DbChangeSource] 是「能提供变更流」的能力接口，由具体
///     `DatabaseProvider` 实现（如 `SqfliteDatabaseProvider`）；
///   * 同步层只依赖 [DbChangeSource]，不反依赖 db 包。
library;

import 'dart:async';

/// 会被同步层关注的实体分区
///
/// 刻意不含 `downloads`：下载任务是设备本地状态，不参与云同步。
enum DbEntity {
  /// 歌曲索引
  songs,

  /// 歌单（含 playlist_songs）
  playlists,

  /// 收藏
  favorites,

  /// 最近播放
  recent,

  /// 播放进度
  progress,

  /// 设置（key-value）
  settings,
}

/// 一次写变更事件
class DbChange {
  /// 发生变更的实体分区
  final DbEntity entity;

  /// 事件时间
  final DateTime at;

  /// 构造
  const DbChange(this.entity, this.at);

  @override
  String toString() => 'DbChange(${entity.name}, $at)';
}

/// 写变更总线：DAO 写成功后 [emit]，订阅方按防抖策略消费
class DbChangeBus {
  final StreamController<DbChange> _controller =
      StreamController<DbChange>.broadcast();

  /// 变更流（广播：允许多个订阅者）
  Stream<DbChange> get changes => _controller.stream;

  /// 发出一次变更（总线已关闭时静默忽略）
  void emit(DbEntity entity) {
    if (_controller.isClosed) return;
    _controller.add(DbChange(entity, DateTime.now()));
  }

  /// 关闭总线（释放资源）
  Future<void> dispose() => _controller.close();
}

/// 「能提供写变更流」的能力接口
///
/// 具体 `DatabaseProvider` 实现它；同步层通过 `provider is DbChangeSource`
/// 判断是否支持自动触发，不支持时退化为手动/启动同步。
abstract interface class DbChangeSource {
  /// 数据库写变更流
  Stream<DbChange> get changes;
}
