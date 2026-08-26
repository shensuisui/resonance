/// 歌单编解码器：M3U / PLS / JSON
///
/// 纯 Dart 实现，用于歌单导入/导出。
/// - M3U: 最通用播放列表格式（#EXTM3U + #EXTINF）
/// - PLS: Winamp 播放列表格式（[playlist] 段）
/// - JSON: 本应用自定义格式（可携带歌单名）

import 'dart:convert';

/// 歌单条目（导入/导出的中间表示）
class PlaylistEntry {
  final String title;
  final String artist;
  final String? url;
  final String? localPath;

  const PlaylistEntry({
    required this.title,
    required this.artist,
    this.url,
    this.localPath,
  });

  /// 可播放来源（优先本地路径）
  String get source => localPath ?? url ?? '';

  /// 显示标题（"Artist - Title"）
  String get displayTitle =>
      artist.isNotEmpty ? '$artist - $title' : title;

  PlaylistEntry copyWith({String? title, String? artist, String? url, String? localPath}) {
    return PlaylistEntry(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      url: url ?? this.url,
      localPath: localPath ?? this.localPath,
    );
  }
}

/// 歌单导入结果
class PlaylistImportResult {
  final String? name;
  final List<PlaylistEntry> entries;

  const PlaylistImportResult({this.name, required this.entries});
}

/// M3U / PLS / JSON 编解码
class PlaylistCodec {
  PlaylistCodec._();

  // ==================== M3U ====================

  /// 编码为 M3U 格式
  ///
  /// 无来源（url 和 localPath 都为空）的条目跳过，
  /// 因为 M3U 无法表示无来源歌曲。
  static String encodeM3U(List<PlaylistEntry> songs) {
    final buffer = StringBuffer('#EXTM3U\n');
    for (final song in songs) {
      if (song.source.isEmpty) continue;
      buffer.writeln('#EXTINF:-1,${song.displayTitle}');
      buffer.writeln(song.source);
    }
    return buffer.toString();
  }

  /// 解析 M3U 格式
  static List<PlaylistEntry> decodeM3U(String content) {
    final entries = <PlaylistEntry>[];
    final lines = content.split(RegExp(r'\r?\n'));

    PlaylistEntry? pending;
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXTM3U')) continue;
      if (line.startsWith('#EXTINF:')) {
        // 提取标题（逗号后部分）
        final comma = line.indexOf(',');
        final title = comma >= 0 ? line.substring(comma + 1).trim() : '';
        pending = _parseDisplayTitle(title);
        continue;
      }
      // 普通行是来源（URL 或本地路径）
      if (line.startsWith('#')) continue; // 其他注释行
      if (pending != null) {
        entries.add(pending.copyWith(url: line, localPath: line));
        pending = null;
      } else {
        // 无 #EXTINF 的直接来源行
        entries.add(PlaylistEntry(
          title: line, artist: '', url: line, localPath: line,
        ));
      }
    }
    return entries;
  }

  // ==================== PLS ====================

  /// 编码为 PLS 格式
  ///
  /// 无来源（url 和 localPath 都为空）的条目跳过，
  /// 因为 PLS 无法表示无来源歌曲。
  static String encodePLS(List<PlaylistEntry> songs) {
    final valid = songs.where((s) => s.source.isNotEmpty).toList();
    final buffer = StringBuffer('[playlist]\n');
    buffer.writeln('NumberOfEntries=${valid.length}');
    for (int i = 0; i < valid.length; i++) {
      final n = i + 1;
      final song = valid[i];
      buffer.writeln('File$n=${song.source}');
      buffer.writeln('Title$n=${song.displayTitle}');
      buffer.writeln('Length$n=-1');
    }
    buffer.writeln('Version=2');
    return buffer.toString();
  }

  /// 解析 PLS 格式
  static List<PlaylistEntry> decodePLS(String content) {
    final fileMap = <int, String>{};
    final titleMap = <int, String>{};

    for (final raw in content.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('[')) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      final value = line.substring(eq + 1).trim();

      // FileN / TitleN
      final fileMatch = RegExp(r'^File(\d+)$', caseSensitive: false).firstMatch(key);
      final titleMatch = RegExp(r'^Title(\d+)$', caseSensitive: false).firstMatch(key);
      if (fileMatch != null) {
        fileMap[int.parse(fileMatch.group(1)!)] = value;
      } else if (titleMatch != null) {
        titleMap[int.parse(titleMatch.group(1)!)] = value;
      }
    }

    // 组装条目（按 File 序号排序）
    final indexes = fileMap.keys.toList()..sort();
    return indexes.map((i) {
      final title = titleMap[i] ?? '';
      return _parseDisplayTitle(title).copyWith(url: fileMap[i], localPath: fileMap[i]);
    }).toList();
  }

  // ==================== JSON ====================

  /// 编码为 JSON 格式（含歌单名）
  static String encodeJson(String name, List<PlaylistEntry> songs) {
    return jsonEncode({
      'name': name,
      'songs': songs
          .map((s) => {
                'title': s.title,
                'artist': s.artist,
                'url': s.url,
                'localPath': s.localPath,
              })
          .toList(),
    });
  }

  /// 解析 JSON 格式
  static PlaylistImportResult decodeJson(String content) {
    try {
      final json = jsonDecode(content) as Map<String, dynamic>;
      final name = json['name'] as String?;
      final songsRaw = json['songs'] as List<dynamic>? ?? [];
      final entries = songsRaw.map((e) {
        final m = e as Map<String, dynamic>;
        return PlaylistEntry(
          title: m['title'] as String? ?? '',
          artist: m['artist'] as String? ?? '',
          url: m['url'] as String?,
          localPath: m['localPath'] as String?,
        );
      }).toList();
      return PlaylistImportResult(name: name, entries: entries);
    } catch (_) {
      return const PlaylistImportResult(entries: []);
    }
  }

  // ==================== 工具 ====================

  /// 解析 "Artist - Title" 显示标题
  static PlaylistEntry _parseDisplayTitle(String displayTitle) {
    final dash = displayTitle.indexOf(' - ');
    if (dash > 0) {
      return PlaylistEntry(
        title: displayTitle.substring(dash + 3).trim(),
        artist: displayTitle.substring(0, dash).trim(),
      );
    }
    return PlaylistEntry(title: displayTitle.trim(), artist: '');
  }
}
