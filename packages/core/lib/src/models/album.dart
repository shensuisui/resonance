import 'song.dart';

/// 专辑模型
class Album {
  final String id;
  final String sourceId;
  final String title;
  final String artist;
  final String? coverUrl;
  final List<Song> songs;
  final int? songCount;
  final Map<String, dynamic> extra;

  const Album({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.artist,
    this.coverUrl,
    this.songs = const [],
    this.songCount,
    this.extra = const {},
  });

  Album copyWith({
    String? id,
    String? sourceId,
    String? title,
    String? artist,
    String? coverUrl,
    List<Song>? songs,
    int? songCount,
    Map<String, dynamic>? extra,
  }) {
    return Album(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      coverUrl: coverUrl ?? this.coverUrl,
      songs: songs ?? this.songs,
      songCount: songCount ?? this.songCount,
      extra: extra ?? this.extra,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Album && id == other.id && sourceId == other.sourceId;

  @override
  int get hashCode => Object.hash(id, sourceId);

  @override
  String toString() => 'Album(id: $id, title: $title)';
}