import 'package:core/core.dart';
import 'engine/rule_config.dart';
import 'engine/value_parse.dart';
import 'engine/rule_executor.dart';

/// 基于规则配置的音乐源实现
/// 将一个 JSON 规则文件转换为一个完整的 MusicSource
class RuleBasedMusicSource extends MusicSource implements ImageHeaderSource {
  final RuleConfig _ruleConfig;
  late final RuleExecutor _executor;

  RuleBasedMusicSource(this._ruleConfig) {
    _executor = RuleExecutor(_ruleConfig);
  }

  @override
  SourceInfo get sourceInfo => SourceInfo(
        id: _ruleConfig.source.id,
        name: _ruleConfig.source.name,
        iconUrl: _ruleConfig.source.icon,
        type: SourceType.rule,
        enabled: true,
        showInLibrary: _ruleConfig.source.showInLibrary,
        visible: _ruleConfig.source.visible,
      );

  @override
  Future<SearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 20,
  }) async {
    return _executor.executeSearch(keyword, page: page);
  }

  @override
  Future<Song> getSongDetail(String id) async =>
      _songFromFields(id, await _executor.executeSongDetail(id));

  @override
  Future<String> getSongUrl(String id) async =>
      _playUrlOf(await _executor.executeSongDetail(id));

  @override
  /// 规则源的详情接口一次就同时给出播放地址与封面/歌手/时长：
  /// 这里复用同一次请求，避免"取地址"与"取封面"各打一次详情（实测两次请求）。
  Future<PlayableInfo> getPlayable(String id) async {
    final fields = await _executor.executeSongDetail(id);
    return PlayableInfo(
      url: _playUrlOf(fields),
      meta: _songFromFields(id, fields),
    );
  }

  /// 详情字段 → 播放地址
  String _playUrlOf(Map<String, dynamic> fields) =>
      parseFieldText(fields['playUrl']) ?? parseFieldText(fields['url']) ?? '';

  /// 详情字段 → 曲目（规则源详情缺失的字段保持为空，不造假）
  Song _songFromFields(String id, Map<String, dynamic> fields) => Song(
        id: id,
        sourceId: _ruleConfig.source.id,
        // 统一走 parseFieldText：多值命中时取首个，
        // 直接 toString() 会把 List 的「[x]」表示法当成标题（真机标题全是 [稻香]）
        title: parseFieldText(fields['title']) ?? '',
        artist: parseFieldText(fields['artist']) ?? '',
        album: parseFieldText(fields['album']),
        coverUrl:
            parseFieldText(fields['cover']) ?? parseFieldText(fields['coverUrl']),
        duration: parseDurationSeconds(parseFieldText(fields['duration'])),
        playUrl: parseFieldText(fields['playUrl']) ?? parseFieldText(fields['url']),
        lyricUrl: parseFieldText(fields['lyricUrl']),
      );

  @override
  Future<Lyrics?> getLyrics(String id) async {
    final lyric = await _executor.executeLyric(id);
    if (lyric == null) return null;
    return Lyrics(
      songId: id,
      sourceId: _ruleConfig.source.id,
      lines: _parseLrc(lyric),
      isLrc: lyric.contains('['),
    );
  }

  @override
  Future<Album?> getAlbum(String id) async => null;

  @override
  Future<Artist?> getArtist(String id) async => null;

  @override
  Future<Playlist?> getPlaylist(String id) async {
    final result = await _executor.executePlaylist(id);
    if (result == null || result.songs.isEmpty) return null;
    return result.playlist;
  }

  /// 歌单完整歌曲列表（executePlaylist 已提取曲目标题/歌手/封面/播放地址）
  @override
  Future<List<Song>> getPlaylistSongs(String id) async {
    final result = await _executor.executePlaylist(id);
    if (result == null) return const [];
    return result.songs;
  }

  /// 获取推荐歌单列表（歌单发现页）
  Future<List<Playlist>> getPlaylistList({int page = 1}) async {
    return _executor.executePlaylistList(page: page);
  }

  /// 播放请求头：播放器请求 CDN 地址时需携带的 HTTP 头
  /// 从规则配置的 playHeaders 字段读取
  Map<String, String> get playHeaders => _ruleConfig.playHeaders ?? {};

  @override
  /// 封面图与播放共用同一套请求头（referer 等），否则 CDN 会 403
  Map<String, String> get imageHeaders => playHeaders;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}

  /// 简单解析 LRC 格式歌词
  List<LyricLine> _parseLrc(String lrc) {
    if (!lrc.contains('[')) {
      return [LyricLine(time: Duration.zero, text: lrc)];
    }
    final lines = <LyricLine>[];
    final regex = RegExp(r'\[(\d{2}):(\d{2})\.?(\d{0,3})\](.*)');
    for (final match in regex.allMatches(lrc)) {
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final millis = (match.group(3)?.length ?? 0) > 0
          ? int.parse(match.group(3)!.padRight(3, '0').substring(0, 3))
          : 0;
      final text = match.group(4)?.trim() ?? '';
      if (text.isNotEmpty) {
        lines.add(LyricLine(
          time: Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: millis,
          ),
          text: text,
        ));
      }
    }
    return lines;
  }
}