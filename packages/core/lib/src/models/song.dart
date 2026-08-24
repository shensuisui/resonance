/// 歌曲模型
class Song {
  /// 源内歌曲 ID
  final String id;

  /// 来源标识，(id, sourceId) 组成全局唯一键
  final String sourceId;

  /// 歌名
  final String title;

  /// 艺术家
  final String artist;

  /// 专辑名
  final String? album;

  /// 封面 URL
  final String? coverUrl;

  /// 时长（秒）
  final int? duration;

  /// 播放地址（可能有时效）
  final String? playUrl;

  /// 歌词文件地址
  final String? lyricUrl;

  /// 歌词文本（若已获取）
  final String? lyric;

  /// 本地缓存路径
  final String? localPath;

  /// 源自定义扩展字段
  final Map<String, dynamic> extra;

  const Song({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.artist,
    this.album,
    this.coverUrl,
    this.duration,
    this.playUrl,
    this.lyricUrl,
    this.lyric,
    this.localPath,
    this.extra = const {},
  });

  /// 全局唯一键
  String get globalKey => '$sourceId:$id';

  Song copyWith({
    String? id,
    String? sourceId,
    String? title,
    String? artist,
    String? album,
    String? coverUrl,
    int? duration,
    String? playUrl,
    String? lyricUrl,
    String? lyric,
    String? localPath,
    Map<String, dynamic>? extra,
  }) {
    return Song(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      coverUrl: coverUrl ?? this.coverUrl,
      duration: duration ?? this.duration,
      playUrl: playUrl ?? this.playUrl,
      lyricUrl: lyricUrl ?? this.lyricUrl,
      lyric: lyric ?? this.lyric,
      localPath: localPath ?? this.localPath,
      extra: extra ?? this.extra,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Song && id == other.id && sourceId == other.sourceId;

  @override
  int get hashCode => Object.hash(id, sourceId);

  @override
  String toString() => 'Song(id: $id, sourceId: $sourceId, title: $title)';
}