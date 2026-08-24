import 'song.dart';

/// 搜索结果
class SearchResult {
  final List<Song> songs;
  final bool hasMore;
  final int? nextPage;
  final int? nextOffset;
  final String? nextCursor;
  final String sourceId;

  const SearchResult({
    required this.songs,
    this.hasMore = false,
    this.nextPage,
    this.nextOffset,
    this.nextCursor,
    required this.sourceId,
  });

  @override
  String toString() =>
      'SearchResult(sourceId: $sourceId, songs: ${songs.length}, hasMore: $hasMore)';
}