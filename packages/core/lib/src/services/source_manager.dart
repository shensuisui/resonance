import 'dart:async';

import 'package:core/core.dart';

/// 源管理器：管理所有音乐源的注册、启用/禁用、聚合搜索调度
///
/// 每个源的操作（搜索/播放地址/歌词等）会写入 [SourceLogBus] 供 UI 排障查看。
class SourceManager {
  final Map<String, MusicSource> _sources = {};
  final Map<String, bool> _enabledStatus = {};

  /// 注册源
  void registerSource(MusicSource source) {
    _sources[source.sourceInfo.id] = source;
    _enabledStatus[source.sourceInfo.id] = source.sourceInfo.enabled;
  }

  /// 取消注册源
  void unregisterSource(String sourceId) {
    _sources.remove(sourceId);
    _enabledStatus.remove(sourceId);
  }

  /// 启用状态变化时的回调（sourceId, enabled）
  ///
  /// 为什么要有它：启用状态的**唯一真相**在这个 manager 里（core 不依赖任何 UI 框架），
  /// 但改它的路径不止一条 —— 设置页、启动时注册内置源、订阅库加载新源……
  /// 宿主（uiv2）用这个回调把「状态变了」通知给 UI，UI 就不再需要自己存第二份 map
  /// （曾经两份并存，绕过 UI 直接改 manager 的路径会让界面失真）。
  void Function(String sourceId, bool enabled)? onEnabledChanged;

  /// 启用/禁用源
  void setSourceEnabled(String sourceId, bool enabled) {
    if (_enabledStatus[sourceId] == enabled) return; // 没变就不通知，避免无谓重建
    _enabledStatus[sourceId] = enabled;
    onEnabledChanged?.call(sourceId, enabled);
  }

  /// 获取源是否启用
  bool isSourceEnabled(String sourceId) {
    return _enabledStatus[sourceId] ?? false;
  }

  /// 获取所有已注册源
  List<MusicSource> getAllSources() => _sources.values.toList();

  /// 获取所有已启用源
  List<MusicSource> getEnabledSources() {
    return _sources.values
        .where((s) => _enabledStatus[s.sourceInfo.id] == true)
        .toList();
  }

  /// 获取指定源
  MusicSource? getSource(String sourceId) => _sources[sourceId];

  /// 聚合搜索：并行搜索所有已启用源
  ///
  /// 单源失败不影响其他源——失败的源返回空结果，并记录错误日志。
  Future<List<SearchResult>> searchAll({
    required String keyword,
    int page = 1,
    int pageSize = 20,
  }) async {
    final sources = getEnabledSources();
    final results = await Future.wait(
      sources.map((s) => _searchOne(s, keyword, page, pageSize)),
      eagerError: false,
    );
    return results;
  }

  /// 逐源返回的聚合搜索：每个源一完成就立刻 emit，**不等其他源**。
  ///
  /// 与 [searchAll] 的分工：[searchAll] 语义是「等齐再给」，适合拿来做整体断言；
  /// 搜索页要的是先回来先上屏，所以用这个流 —— 按到达顺序消费即可，
  /// 顺序不作保证（谁快谁先）。
  Stream<SearchResult> searchStream({
    required String keyword,
    int page = 1,
    int pageSize = 20,
  }) {
    final sources = getEnabledSources();
    final controller = StreamController<SearchResult>();
    if (sources.isEmpty) {
      controller.close();
      return controller.stream;
    }
    var pending = sources.length;
    for (final s in sources) {
      unawaited(
        _searchOne(s, keyword, page, pageSize).then((r) {
          if (controller.isClosed) return;
          controller.add(r);
          pending--;
          if (pending == 0) controller.close();
        }),
      );
    }
    return controller.stream;
  }

  /// 搜一个源（带日志与错误吞掉：单源失败只返回空结果，不影响其他源）
  Future<SearchResult> _searchOne(
    MusicSource s,
    String keyword,
    int page,
    int pageSize,
  ) async {
    final sw = Stopwatch()..start();
    final sid = s.sourceInfo.id;
    SourceLogBus.instance.emit(
        sid, SourceLogLevel.info, '搜索', '开始搜索「$keyword」');
    try {
      final r = await s.search(
        keyword: keyword,
        page: page,
        pageSize: pageSize,
      );
      SourceLogBus.instance.emit(
        sid,
        SourceLogLevel.info,
        '搜索',
        '完成「$keyword」：${r.songs.length} 首，耗时 ${sw.elapsedMilliseconds}ms',
      );
      return r;
    } catch (e) {
      SourceLogBus.instance.emit(
        sid,
        SourceLogLevel.error,
        '搜索',
        '失败：$e',
      );
      return SearchResult(songs: [], sourceId: sid);
    }
  }

  /// 获取指定源的歌曲详情
  Future<Song> getSongDetail(String sourceId, String songId) async {
    final source = _sources[sourceId];
    if (source == null) {
      throw Exception('Source not found: $sourceId');
    }
    final sw = Stopwatch()..start();
    try {
      final song = await source.getSongDetail(songId);
      SourceLogBus.instance.emit(
        sourceId,
        SourceLogLevel.info,
        '歌曲详情',
        'id=$songId 完成，耗时 ${sw.elapsedMilliseconds}ms',
      );
      return song;
    } catch (e) {
      SourceLogBus.instance.emit(
        sourceId,
        SourceLogLevel.error,
        '歌曲详情',
        'id=$songId 失败：$e',
      );
      rethrow;
    }
  }

  /// 该源的播放请求头（referer 等）；源没声明则为空
  ///
  /// 规则源的详情接口与音频 CDN 共用同一套头，所以直接读 ImageHeaderSource。
  Map<String, String> playHeadersFor(String sourceId) {
    final source = _sources[sourceId];
    if (source == null) return const {};
    if (source is ImageHeaderSource) {
      // 显式转换：ImageHeaderSource 与 MusicSource 无继承关系，类型提升不生效
      return (source as ImageHeaderSource).imageHeaders;
    }
    return const {};
  }

  /// 获取指定源的播放地址，并尽可能顺带带回元数据
  ///
  /// 这是播放地址的唯一实现：[getSongUrl] 只是取它的地址。
  Future<PlayableInfo> getPlayable(String sourceId, String songId,
      {String? captchaCode, String? captchaKey}) async {
    final source = _sources[sourceId];
    if (source == null) {
      throw Exception('Source not found: $sourceId');
    }
    final sw = Stopwatch()..start();
    try {
      final info = await source.getPlayable(songId,
          captchaCode: captchaCode, captchaKey: captchaKey);
      SourceLogBus.instance.emit(
        sourceId,
        (info.url.isEmpty && !info.needsChallenge)
            ? SourceLogLevel.warn
            : SourceLogLevel.info,
        '播放URL',
        'id=$songId '
            '${info.needsChallenge ? '源站要求人机验证' : (info.url.isEmpty ? '未返回地址' : '成功')}'
            '${info.meta == null ? '' : '（含元数据）'}，耗时 ${sw.elapsedMilliseconds}ms',
      );
      return info;
    } catch (e) {
      SourceLogBus.instance.emit(
        sourceId,
        SourceLogLevel.error,
        '播放URL',
        'id=$songId 失败：$e',
      );
      rethrow;
    }
  }

  /// 获取指定源的歌曲播放 URL
  Future<String> getSongUrl(String sourceId, String songId) async =>
      (await getPlayable(sourceId, songId)).url;

  /// 获取指定源的歌词
  Future<Lyrics?> getLyrics(String sourceId, String songId) async {
    final source = _sources[sourceId];
    if (source == null) throw Exception('Source not found: $sourceId');
    final sw = Stopwatch()..start();
    try {
      final lyrics = await source.getLyrics(songId);
      SourceLogBus.instance.emit(
        sourceId,
        SourceLogLevel.info,
        '歌词',
        'id=$songId ${lyrics == null ? '无歌词' : '${lyrics.lines.length} 行'}，'
            '耗时 ${sw.elapsedMilliseconds}ms',
      );
      return lyrics;
    } catch (e) {
      SourceLogBus.instance.emit(
        sourceId,
        SourceLogLevel.error,
        '歌词',
        'id=$songId 失败：$e',
      );
      rethrow;
    }
  }

  /// 初始化所有已注册源
  Future<void> initAll() async {
    await Future.wait(_sources.values.map((s) {
      SourceLogBus.instance.emit(
          s.sourceInfo.id, SourceLogLevel.info, '初始化', '开始');
      return s.init();
    }));
  }

  /// 释放所有源
  Future<void> disposeAll() async {
    await Future.wait(_sources.values.map((s) {
      SourceLogBus.instance.emit(
          s.sourceInfo.id, SourceLogLevel.info, '释放', '开始');
      return s.dispose();
    }));
  }
}