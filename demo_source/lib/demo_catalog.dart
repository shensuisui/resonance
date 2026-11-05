import 'dart:convert';
import 'dart:io';

/// 演示曲目（服务端内部模型）
class DemoTrack {
  final String id;
  final int no;
  final String title;
  final String artist;
  final String albumId;
  final String album;
  final String genre;
  final int duration;
  final bool local;
  final bool downloaded;
  final String sourceId;

  const DemoTrack({
    required this.id,
    required this.no,
    required this.title,
    required this.artist,
    required this.albumId,
    required this.album,
    required this.genre,
    required this.duration,
    required this.local,
    required this.downloaded,
    required this.sourceId,
  });
}

/// 演示专辑
class DemoAlbum {
  final String id;
  final String title;
  final String artist;
  final int year;
  final String genre;
  final bool imported;
  final bool downloaded;
  final List<DemoTrack> tracks;

  const DemoAlbum({
    required this.id,
    required this.title,
    required this.artist,
    required this.year,
    required this.genre,
    required this.imported,
    required this.downloaded,
    required this.tracks,
  });
}

/// 演示歌单
class DemoPlaylist {
  final String id;
  final String name;
  final String desc;
  final String color;
  final String colorDark;
  final List<String> refs;
  final bool user;

  const DemoPlaylist({
    required this.id,
    required this.name,
    required this.desc,
    required this.color,
    required this.colorDark,
    required this.refs,
    required this.user,
  });
}

/// 演示目录：从 JSON 加载，负责搜索、详情和歌单解析。
class DemoCatalog {
  final List<DemoAlbum> albums;
  final List<DemoTrack> tracks;
  final List<DemoPlaylist> playlists;
  final Map<String, DemoTrack> _trackById;
  final Map<String, DemoPlaylist> _playlistById;

  DemoCatalog._({
    required this.albums,
    required this.tracks,
    required this.playlists,
    required Map<String, DemoTrack> trackById,
    required Map<String, DemoPlaylist> playlistById,
  })  : _trackById = trackById,
        _playlistById = playlistById;

  /// 从真实数据文件加载
  static Future<DemoCatalog> load(File file) async {
    final raw = jsonDecode(await file.readAsString());
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('catalog.json 根节点必须是对象');
    }
    return DemoCatalog.fromJson(raw);
  }

  /// 从已解析 JSON 构造
  factory DemoCatalog.fromJson(Map<String, dynamic> json) {
    final albumsRaw = (json['albums'] as List<dynamic>? ?? const []);
    final importedAlbumIds =
        (json['importedAlbumIds'] as List<dynamic>? ?? const []).cast<String>().toSet();
    final downloadedAlbumIds =
        (json['downloadedAlbumIds'] as List<dynamic>? ?? const []).cast<String>().toSet();
    final importedExtraTrackIds =
        (json['importedExtraTrackIds'] as List<dynamic>? ?? const [])
            .cast<String>()
            .map(normalizeId)
            .toSet();
    final sourceByAlbum =
        (json['sourceByAlbum'] as Map<String, dynamic>? ?? const {}).cast<String, String>();
    final sourceByTrack = <String, String>{
      for (final entry in (json['sourceByTrack'] as Map<String, dynamic>? ?? const {})
          .cast<String, String>()
          .entries)
        normalizeId(entry.key): entry.value,
    };

    final albums = <DemoAlbum>[];
    final tracks = <DemoTrack>[];
    final trackById = <String, DemoTrack>{};
    for (final albumRaw in albumsRaw.cast<Map<String, dynamic>>()) {
      final albumId = albumRaw['id'] as String;
      final imported = importedAlbumIds.contains(albumId);
      final downloaded = downloadedAlbumIds.contains(albumId);
      final names = (albumRaw['tracks'] as List<dynamic>).cast<String>();
      final albumTracks = <DemoTrack>[];
      for (var i = 0; i < names.length; i++) {
        // 旧配表 id 形如 midnights#3；对外必须用 URL 安全形式，
        // 否则规则引擎拼出的 /songs/midnights#3 里 # 会被当作 fragment。
        final rawId = '$albumId#${i + 1}';
        final id = normalizeId(rawId);
        final track = DemoTrack(
          id: id,
          no: i + 1,
          title: names[i],
          artist: albumRaw['artist'] as String,
          albumId: albumId,
          album: albumRaw['title'] as String,
          genre: albumRaw['genre'] as String,
          duration: makeDuration(rawId),
          local: imported || importedExtraTrackIds.contains(id),
          downloaded: downloaded,
          sourceId: sourceByTrack[id] ?? sourceByAlbum[albumId] ?? 'local',
        );
        albumTracks.add(track);
        tracks.add(track);
        trackById[id] = track;
      }
      albums.add(DemoAlbum(
        id: albumId,
        title: albumRaw['title'] as String,
        artist: albumRaw['artist'] as String,
        year: (albumRaw['year'] as num).toInt(),
        genre: albumRaw['genre'] as String,
        imported: imported,
        downloaded: downloaded,
        tracks: albumTracks,
      ));
    }

    final playlists = <DemoPlaylist>[];
    final playlistById = <String, DemoPlaylist>{};
    for (final item in (json['playlists'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()) {
      final playlist = DemoPlaylist(
        id: item['id'] as String,
        name: item['name'] as String,
        desc: item['desc'] as String,
        color: item['color'] as String,
        colorDark: item['colorDark'] as String,
        refs: (item['refs'] as List<dynamic>).cast<String>(),
        user: item['user'] as bool? ?? false,
      );
      playlists.add(playlist);
      playlistById[playlist.id] = playlist;
    }

    return DemoCatalog._(
      albums: albums,
      tracks: tracks,
      playlists: playlists,
      trackById: trackById,
      playlistById: playlistById,
    );
  }

  /// 加载歌词 JSON（曲目 id → 原始行列表）
  static Future<Map<String, List<String>>> loadLyrics(File file) async {
    final raw = jsonDecode(await file.readAsString());
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('lyrics.json 根节点必须是对象');
    }
    return raw.map((key, value) => MapEntry(
          normalizeId(key),
          (value as List<dynamic>).cast<String>(),
        ));
  }

  /// 按 id 取曲目（兼容旧配表的 `#` 写法）
  DemoTrack? track(String id) => _trackById[normalizeId(id)];

  /// 按 id 取歌单
  DemoPlaylist? playlist(String id) => _playlistById[id];

  /// 批量解析曲目引用（引用沿用旧配表写法，如 `midnights#3`）
  List<DemoTrack> resolve(List<String> refs) => refs
      .map((ref) => _trackById[normalizeId(ref)])
      .whereType<DemoTrack>()
      .toList();

  /// 对外 id 用 URL 安全形式；`#` 会被 HTTP 当成 fragment，服务端收不到后半段。
  static String normalizeId(String id) => id.replaceFirst('#', '-');

  /// 搜索：歌名、艺人、专辑、流派四个字段。空关键词返回空。
  List<DemoTrack> search(String keyword, {required int page, int pageSize = 20}) {
    final q = keyword.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final hits = tracks
        .where((track) =>
            '${track.title} ${track.artist} ${track.album} ${track.genre}'
                .toLowerCase()
                .contains(q))
        .toList();
    final safePage = page < 1 ? 1 : page;
    final safeSize = pageSize < 1 ? 20 : pageSize;
    final start = ((safePage - 1) * safeSize).clamp(0, hits.length);
    final end = (start + safeSize).clamp(0, hits.length);
    return hits.sublist(start, end);
  }

  /// 全部曲目数量是否提示还有下一页
  bool searchHasMore(String keyword, {required int page, int pageSize = 20}) {
    final q = keyword.trim().toLowerCase();
    if (q.isEmpty) return false;
    final count = tracks
        .where((track) =>
            '${track.title} ${track.artist} ${track.album} ${track.genre}'
                .toLowerCase()
                .contains(q))
        .length;
    return page * pageSize < count;
  }

  /// UI 目录快照（封面、播放地址都是绝对 URL）
  Map<String, dynamic> toCatalogJson(String origin) => {
        'albums': [
          for (final album in albums)
            {
              'id': album.id,
              'title': album.title,
              'artist': album.artist,
              'year': album.year,
              'genre': album.genre,
              'cover': '$origin/covers/${album.id}.jpg',
              'imported': album.imported,
              'downloaded': album.downloaded,
              'tracks': [for (final track in album.tracks) track.id],
            },
        ],
        'tracks': [for (final track in tracks) trackJson(track, origin)],
      };

  /// 曲目 JSON。额外字段会被规则执行器放进 Song.extra，保留展示信息。
  Map<String, dynamic> trackJson(DemoTrack track, String origin) => {
        'id': track.id,
        'no': track.no,
        'title': track.title,
        'artist': track.artist,
        'albumId': track.albumId,
        'album': track.album,
        'coverUrl': '$origin/covers/${track.albumId}.jpg',
        'genre': track.genre,
        'duration': track.duration,
        'local': track.local,
        'downloaded': track.downloaded,
        'sourceId': track.sourceId,
        'playUrl': '$origin/audio/demo.wav',
      };

  /// 歌单列表项
  Map<String, dynamic> playlistJson(DemoPlaylist playlist, String origin) {
    final songs = resolve(playlist.refs);
    return {
      'id': playlist.id,
      'name': playlist.name,
      'desc': playlist.desc,
      'color': playlist.color,
      'colorDark': playlist.colorDark,
      'user': playlist.user,
      'coverUrl': songs.isEmpty ? null : '$origin/covers/${songs.first.albumId}.jpg',
    };
  }

  /// 默认曲目时长算法，必须与旧 App 内的实现保持一致。
  static int makeDuration(String seed) {
    var h = 0;
    for (var i = 0; i < seed.length; i++) {
      h = (h * 31 + seed.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return 148 + (h * 37) % 214;
  }
}
