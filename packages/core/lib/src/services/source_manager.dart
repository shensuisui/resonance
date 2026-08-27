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

  /// 启用/禁用源
  void setSourceEnabled(String sourceId, bool enabled) {
    _enabledStatus[sourceId] = enabled;
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
      sources.map((s) async {
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
      }),
      eagerError: false,
    );
    return results;
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

  /// 获取指定源的歌曲播放 URL
  Future<String> getSongUrl(String sourceId, String songId) async {
    final source = _sources[sourceId];
    if (source == null) {
      throw Exception('Source not found: $sourceId');
    }
    final sw = Stopwatch()..start();
    try {
      final url = await source.getSongUrl(songId);
      SourceLogBus.instance.emit(
        sourceId,
        url.isEmpty ? SourceLogLevel.warn : SourceLogLevel.info,
        '播放URL',
        'id=$songId ${url.isEmpty ? '未返回地址' : '成功'}，耗时 ${sw.elapsedMilliseconds}ms',
      );
      return url;
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