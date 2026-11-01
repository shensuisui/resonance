import 'package:core/core.dart';

/// 「图片请求需要额外请求头」的源契约
///
/// 有些站点（如枫叶音乐盒）封面走 CDN 且校验 referer，
/// 直接 Image.network 会 403。单独抽契约而不是塞进 [MusicSource]：
/// 一是不必改所有实现，二是只有需要的源才实现。
abstract class ImageHeaderSource {
  /// 加载该源图片时要带的请求头
  Map<String, String> get imageHeaders;
}

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

  /// 获取歌单的完整歌曲列表（含元数据与播放地址）
  ///
  /// 默认实现返回空——无歌单歌曲能力的源不需要覆盖。
  Future<List<Song>> getPlaylistSongs(String id) async => const [];

  /// 获取歌单列表（推荐歌单等）
  ///
  /// 默认实现返回空列表（无歌单列表能力的源不需要覆盖）。
  Future<List<Playlist>> getPlaylistList({int page = 1}) async => const [];

  /// 初始化源（如加载配置、建立连接）
  Future<void> init();

  /// 释放源资源
  Future<void> dispose();
}