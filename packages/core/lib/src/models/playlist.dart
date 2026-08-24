/// 歌单模型
class Playlist {
  final String id;
  final String name;
  final List<String> songKeys;
  final String? sourceId;
  final String? sourcePlaylistId;
  final String? coverUrl;
  final DateTime createdTime;
  final DateTime modifiedTime;

  const Playlist({
    required this.id,
    required this.name,
    this.songKeys = const [],
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