/// 歌单模型
import 'song.dart';

class Playlist {
  final String id;
  final String name;
  final List<String> songKeys;
  /// 歌曲快照：songKey → Song（含 title/artist/coverUrl/duration）
  ///
  /// 规则源 getSongDetail 只返回播放地址不返回元数据（历史上三次导致
  /// 最近播放/收藏/自定义歌单名称空白），歌单在写入时保存歌曲快照，
  /// 列表/详情直接展示快照，播放地址再按需解析。
  final Map<String, Song> songSnapshots;
  final String? sourceId;
  final String? sourcePlaylistId;
  final String? coverUrl;
  final DateTime createdTime;
  final DateTime modifiedTime;

  const Playlist({
    required this.id,
    required this.name,
    this.songKeys = const [],
    this.songSnapshots = const {},
    this.sourceId,
    this.sourcePlaylistId,
    this.coverUrl,
    required this.createdTime,
    required this.modifiedTime,
  });

  Playlist copyWith({
    String? id,
    String? name,
    List<String>? songKeys,
    Map<String, Song>? songSnapshots,
    String? sourceId,
    String? sourcePlaylistId,
    String? coverUrl,
    DateTime? createdTime,
    DateTime? modifiedTime,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      songKeys: songKeys ?? this.songKeys,
      songSnapshots: songSnapshots ?? this.songSnapshots,
      sourceId: sourceId ?? this.sourceId,
      sourcePlaylistId: sourcePlaylistId ?? this.sourcePlaylistId,
      coverUrl: coverUrl ?? this.coverUrl,
      createdTime: createdTime ?? this.createdTime,
      modifiedTime: modifiedTime ?? this.modifiedTime,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Playlist && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Playlist(id: $id, name: $name, songs: ${songKeys.length})';
}