import 'package:core/core.dart';

/// 所有音乐源必须实现的抽象接口
abstract class MusicSource {
  /// 源信息
  SourceInfo get sourceInfo;

  /// 搜索歌曲
  Future<SearchResult> search({
    required String keyword,
    int page = 1,
    int pageSize = 20,
  });

  /// 获取歌曲详情（播放地址、歌词等）
  Future<Song> getSongDetail(String id);

  /// 获取歌曲播放 URL
  Future<String> getSongUrl(String id);

  /// 获取歌词
  Future<Lyrics?> getLyrics(String id);

  /// 获取专辑详情
  Future<Album?> getAlbum(String id);

  /// 获取艺术家详情
  Future<Artist?> getArtist(String id);

  /// 获取歌单
  Future<Playlist?> getPlaylist(String id);

  /// 初始化源（如加载配置、建立连接）
  Future<void> init();

  /// 释放源资源
  Future<void> dispose();
}