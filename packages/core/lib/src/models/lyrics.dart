/// 歌词行
class LyricLine {
  final Duration time;
  final String text;

  const LyricLine({required this.time, required this.text});

  @override
  String toString() => '[${time.inMilliseconds}] $text';
}

/// 歌词模型
class Lyrics {
  final String songId;
  final String sourceId;
  final List<LyricLine> lines;
  final bool isLrc;

  const Lyrics({
    required this.songId,
    required this.sourceId,
    this.lines = const [],
    this.isLrc = true,
  });

  Lyrics copyWith({
    String? songId,
    String? sourceId,
    List<LyricLine>? lines,
    bool? isLrc,
  }) {
    return Lyrics(
      songId: songId ?? this.songId,
      sourceId: sourceId ?? this.sourceId,
      lines: lines ?? this.lines,
      isLrc: isLrc ?? this.isLrc,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Lyrics && songId == other.songId && sourceId == other.sourceId;

  @override
  int get hashCode => Object.hash(songId, sourceId);

  @override
  String toString() => 'Lyrics(songId: $songId, lines: ${lines.length})';
}