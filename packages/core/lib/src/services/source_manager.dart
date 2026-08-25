import 'package:core/core.dart';

/// 源管理器：管理所有音乐源的注册、启用/禁用、聚合搜索调度
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
  /// 单源失败不影响其他源——失败的源返回空结果。
  Future<List<SearchResult>> searchAll({
    required String keyword,
    int page = 1,
    int pageSize = 20,
  }) async {
    final sources = getEnabledSources();
    final results = await Future.wait(
      sources.map((s) => s.search(
            keyword: keyword,
            page: page,
            pageSize: pageSize,
          ).catchError((_) => SearchResult(songs: [], sourceId: s.sourceInfo.id))),
      eagerError: false,
    );
    return results;
  }

  /// 获取指定源的歌曲详情
  Future<Song> getSongDetail(String sourceId, String songId) async {
    final source = _sources[sourceId];
    if (source == null) throw Exception('Source not found: $sourceId');
    return source.getSongDetail(songId);
  }

  /// 获取指定源的歌曲播放 URL
  Future<String> getSongUrl(String sourceId, String songId) async {
    final source = _sources[sourceId];
    if (source == null) throw Exception('Source not found: $sourceId');
    return source.getSongUrl(songId);
  }

  /// 获取指定源的歌词
  Future<Lyrics?> getLyrics(String sourceId, String songId) async {
    final source = _sources[sourceId];
    if (source == null) throw Exception('Source not found: $sourceId');
    return source.getLyrics(songId);
  }

  /// 初始化所有已注册源
  Future<void> initAll() async {
    await Future.wait(_sources.values.map((s) => s.init()));
  }

  /// 释放所有源
  Future<void> disposeAll() async {
    await Future.wait(_sources.values.map((s) => s.dispose()));
  }
}