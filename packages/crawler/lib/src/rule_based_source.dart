import 'package:core/core.dart';
import 'engine/rule_config.dart';
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
  Future<Song> getSongDetail(String id) async {
    final fields = await _executor.executeSongDetail(id);
    return Song(
      id: id,
      sourceId: _ruleConfig.source.id,
      title: fields['title']?.toString() ?? '',
      artist: fields['artist']?.toString() ?? '',
      album: fields['album']?.toString(),
      coverUrl: fields['cover']?.toString() ?? fields['coverUrl']?.toString(),
      duration: _parseInt(fields['duration']),
      playUrl: fields['playUrl']?.toString() ?? fields['url']?.toString(),
      lyricUrl: fields['lyricUrl']?.toString(),
    );
  }

  @override
  Future<String> getSongUrl(String id) async {
    final fields = await _executor.executeSongDetail(id);
    return fields['playUrl']?.toString() ?? fields['url']?.toString() ?? '';
  }

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

  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

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