/// 播放缓存（离线可用）契约
///
/// 与 [DownloadManager] 的语义区别：
///   * 下载 = 用户主动要的 → 写 Song.localPath，进「已下载」分栏；
///   * 播放缓存 = 为了「下次不再请求远程」自动存的 → **不碰 localPath**。
///
/// 命中只认**完整文件**：下载中写 `.part`，完整后改名；半截文件绝不参与播放
/// （just_audio 播"还在增长的文件"会出现时长/seek 不准甚至提前结束）。
library;

import 'dart:async';

import '../models/song.dart';

/// 播放缓存（离线可用）契约
abstract class AudioCache {
  /// 启动时扫描缓存目录，建立内存索引（UI 需要同步判断「离线可用」）
  Future<void> init();

  /// 已完整缓存的曲目键集合（同步读取）
  Set<String> get cachedKeys;

  /// 这首歌是否有可离线播放的完整缓存
  bool isCached(String songKey);

  /// 缓存文件的播放地址（file://）；没有则 null
  String? localUrlFor(String songKey);

  /// 用户主动下载过的文件播放地址（file://，且文件真实存在）；没有则 null
  Future<String?> downloadedUrlFor(Song song);

  /// 起播成功后异步缓存一份（失败静默、同首去重、已下载的不重复存）
  Future<void> cacheAfterPlay(Song song, String url,
      {Map<String, String>? headers});

  /// 缓存占用字节数（含下载中的 .part）
  Future<int> sizeOnDisk();

  /// 清空播放缓存（只删本缓存目录，不动「已下载」的文件）
  Future<void> clear();

  /// 缓存发生变化（新增 / 清空）时触发，供 UI 刷新「离线可用」标记
  Stream<void> get changes;
}

/// 缓存文件的物理访问能力（供下载「拷贝缓存」使用，不扩大 AudioCache 契约）
abstract class AudioCacheFileAccess {
  /// 完整缓存文件的真实路径；没有/未初始化/未命中返回 null
  String? filePathFor(String songKey);

  /// 删除单曲缓存（文件 + 索引 + 通知）
  Future<void> remove(String songKey);
}

/// 流式缓存写入（「甲」边播边落盘）
abstract class AudioCacheStreamSink {
  /// 追加一段字节
  Future<void> add(List<int> bytes);

  /// 完成：完整才改名入索引；生成代际变化/空文件则丢弃
  Future<void> commit();

  /// 中止：删掉 .part，不留残片
  Future<void> abort();
}

/// 打开流式写入的能力（不扩大 AudioCache 契约）
abstract class AudioCacheStreamWriter {
  /// 为 songKey 打开 .part 写入；同曲已有写入会先 abort
  Future<AudioCacheStreamSink> openStream(String songKey);
}
