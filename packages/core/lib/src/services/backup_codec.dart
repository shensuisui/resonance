/// 整包备份的编解码（纯 Dart，无 IO、无平台依赖）
///
/// 文件形态：单个 .json，魔数 + 版本 + 逐表内容。与 [PlaylistCodec] 的分工：
///   * 本文件是「回归响」的无损格式（保留 song_key / 来源 / 元数据快照 / 进度）；
///   * PlaylistCodec 是「对外」的交换格式（M3U/PLS/JSON），有损但通用。
///
/// 版本策略：解码只接受 version <= [kBackupVersion]；更高版本直接报错，
/// 不猜测字段（宁可让用户升级 App，也不要把新数据读坏）。
library;

import 'dart:convert';

/// 备份文件魔数（用于识别"这是不是回响的备份"）
const String kBackupFormat = 'resonance-backup';

/// 当前备份结构版本
const int kBackupVersion = 1;

/// 备份内容损坏/版本不兼容时抛出（消息面向用户）
class BackupException implements Exception {
  /// 面向用户的错误说明
  final String message;

  /// 构造
  const BackupException(this.message);

  @override
  String toString() => message;
}

/// 备份里的单首歌
///
/// songKey 是 [Song.globalKey]（sourceId:id），换设备后仍可按来源重新解析地址；
/// 标题/歌手/时长/封面是快照，保证列表在离线或源失效时也能显示。
class BackupSong {
  /// 全局歌曲键（sourceId:id）
  final String songKey;

  /// 歌名快照
  final String title;

  /// 歌手快照
  final String artist;

  /// 时长（毫秒，可空）
  final int? duration;

  /// 封面 URL（可空）
  final String? coverUrl;

  /// 本地文件路径（可空；跨设备通常无效，仅同机恢复有意义）
  final String? localPath;

  /// 构造
  const BackupSong({
    required this.songKey,
    required this.title,
    required this.artist,
    this.duration,
    this.coverUrl,
    this.localPath,
  });
}

/// 备份里的一个歌单（名称 + 有序曲目）
class BackupPlaylist {
  /// 歌单名
  final String name;

  /// 曲目（保持原顺序）
  final List<BackupSong> songs;

  /// 构造
  const BackupPlaylist({required this.name, required this.songs});
}

/// 备份里的一条收藏
class BackupFavorite {
  /// 全局歌曲键
  final String songKey;

  /// 收藏时间（毫秒）
  final int time;

  /// 歌名快照
  final String? title;

  /// 歌手快照
  final String? artist;

  /// 封面快照
  final String? coverUrl;

  /// 构造
  const BackupFavorite({
    required this.songKey,
    required this.time,
    this.title,
    this.artist,
    this.coverUrl,
  });
}

/// 备份里的一条最近播放
class BackupRecent {
  /// 全局歌曲键
  final String songKey;

  /// 播放时间（毫秒）
  final int playedAt;

  /// 歌名快照
  final String? title;

  /// 歌手快照
  final String? artist;

  /// 封面快照
  final String? coverUrl;

  /// 构造
  const BackupRecent({
    required this.songKey,
    required this.playedAt,
    this.title,
    this.artist,
    this.coverUrl,
  });
}

/// 备份里的一条播放进度
class BackupProgress {
  /// 队列种类（recent / playlist / liked / local）
  final String queueKind;

  /// 队列 id（歌单为歌单 id，其它为空串）
  final String queueId;

  /// 曲目全局键
  final String songKey;

  /// 毫秒进度
  final int positionMs;

  /// 最后更新时间（毫秒）
  final int updatedAt;

  /// 构造
  const BackupProgress({
    required this.queueKind,
    required this.songKey,
    required this.positionMs,
    required this.updatedAt,
    this.queueId = '',
  });
}

/// 一份完整备份文档
class BackupDocument {
  /// 导出时间
  final DateTime exportedAt;

  /// 歌单
  final List<BackupPlaylist> playlists;

  /// 收藏
  final List<BackupFavorite> favorites;

  /// 最近播放
  final List<BackupRecent> recent;

  /// 设置（仅白名单键，见 BackupService.exportableSettingKeys）
  final Map<String, String> settings;

  /// 播放进度
  final List<BackupProgress> progress;

  /// 构造
  const BackupDocument({
    required this.exportedAt,
    this.playlists = const <BackupPlaylist>[],
    this.favorites = const <BackupFavorite>[],
    this.recent = const <BackupRecent>[],
    this.settings = const <String, String>{},
    this.progress = const <BackupProgress>[],
  });

  /// 逐表计数（写进文件的 stats，也是 UI 上「备份了什么」的依据）
  Map<String, int> get stats => <String, int>{
        'playlists': playlists.length,
        'songs': playlists.fold<int>(0, (sum, p) => sum + p.songs.length),
        'favorites': favorites.length,
        'recent': recent.length,
        'settings': settings.length,
        'progress': progress.length,
      };
}

/// 备份 JSON 编解码
class BackupCodec {
  BackupCodec._();

  /// 编码成便于阅读的 JSON 文本（缩进 2 空格，方便用户自己检查/改）
  static String encode(BackupDocument doc) {
    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'format': kBackupFormat,
      'version': kBackupVersion,
      'exportedAt': doc.exportedAt.toUtc().toIso8601String(),
      'stats': doc.stats,
      'playlists': <Map<String, dynamic>>[
        for (final playlist in doc.playlists)
          <String, dynamic>{
            'name': playlist.name,
            'songs': <Map<String, dynamic>>[
              for (final song in playlist.songs) _songToJson(song),
            ],
          },
      ],
      'favorites': <Map<String, dynamic>>[
        for (final item in doc.favorites)
          <String, dynamic>{
            'songKey': item.songKey,
            'time': item.time,
            'title': item.title,
            'artist': item.artist,
            'coverUrl': item.coverUrl,
          },
      ],
      'recent': <Map<String, dynamic>>[
        for (final item in doc.recent)
          <String, dynamic>{
            'songKey': item.songKey,
            'playedAt': item.playedAt,
            'title': item.title,
            'artist': item.artist,
            'coverUrl': item.coverUrl,
          },
      ],
      'settings': doc.settings,
      'progress': <Map<String, dynamic>>[
        for (final item in doc.progress)
          <String, dynamic>{
            'queueKind': item.queueKind,
            'queueId': item.queueId,
            'songKey': item.songKey,
            'positionMs': item.positionMs,
            'updatedAt': item.updatedAt,
          },
      ],
    });
  }

  /// 解析备份文本
  ///
  /// 抛 [BackupException]：不是 JSON / 不是回响备份 / 版本过新 / 结构损坏。
  static BackupDocument decode(String content) {
    final Object? raw;
    try {
      raw = jsonDecode(content);
    } on FormatException {
      throw const BackupException('这个文件不是 JSON，无法作为备份导入');
    }
    if (raw is! Map) {
      throw const BackupException('备份文件的顶层结构不对（应为对象）');
    }
    final map = raw.cast<String, dynamic>();

    final format = map['format'];
    if (format != kBackupFormat) {
      // 兼容 v1 时代的「单歌单 JSON」（{name, songs:[...]}）：交给调用方决定
      if (map.containsKey('songs') && format == null) {
        throw const BackupException('这是旧版单歌单文件，请在歌单详情页导入');
      }
      throw const BackupException('这不是回响的备份文件');
    }

    final version = _asInt(map['version']) ?? 0;
    if (version <= 0) {
      throw const BackupException('备份文件缺少版本号，无法判断兼容性');
    }
    if (version > kBackupVersion) {
      throw BackupException(
          '备份版本（v$version）高于当前 App 支持的 v$kBackupVersion，请先升级 App');
    }

    return BackupDocument(
      exportedAt: _asDate(map['exportedAt']),
      playlists: <BackupPlaylist>[
        for (final item in _asList(map['playlists']))
          if (item is Map)
            BackupPlaylist(
              name: (item['name'] as Object?)?.toString() ?? '未命名歌单',
              songs: <BackupSong>[
                for (final song in _asList(item['songs']))
                  if (song is Map) _songFromJson(song.cast<String, dynamic>()),
              ],
            ),
      ],
      favorites: <BackupFavorite>[
        for (final item in _asList(map['favorites']))
          if (item is Map && (item['songKey'] as Object?) != null)
            BackupFavorite(
              songKey: item['songKey'].toString(),
              time: _asInt(item['time']) ?? 0,
              title: (item['title'] as Object?)?.toString(),
              artist: (item['artist'] as Object?)?.toString(),
              coverUrl: (item['coverUrl'] as Object?)?.toString(),
            ),
      ],
      recent: <BackupRecent>[
        for (final item in _asList(map['recent']))
          if (item is Map && (item['songKey'] as Object?) != null)
            BackupRecent(
              songKey: item['songKey'].toString(),
              playedAt: _asInt(item['playedAt']) ?? 0,
              title: (item['title'] as Object?)?.toString(),
              artist: (item['artist'] as Object?)?.toString(),
              coverUrl: (item['coverUrl'] as Object?)?.toString(),
            ),
      ],
      settings: <String, String>{
        for (final entry in (map['settings'] is Map
                ? (map['settings'] as Map).entries
                : const <MapEntry<dynamic, dynamic>>[]))
          if (entry.value != null) entry.key.toString(): entry.value.toString(),
      },
      progress: <BackupProgress>[
        for (final item in _asList(map['progress']))
          if (item is Map && (item['songKey'] as Object?) != null)
            BackupProgress(
              queueKind: (item['queueKind'] as Object?)?.toString() ?? 'recent',
              queueId: (item['queueId'] as Object?)?.toString() ?? '',
              songKey: item['songKey'].toString(),
              positionMs: _asInt(item['positionMs']) ?? 0,
              updatedAt: _asInt(item['updatedAt']) ?? 0,
            ),
      ],
    );
  }

  /// 解析 v1 时代的单歌单 JSON（{name, songs:[{title,artist,url,localPath}]}）
  ///
  /// 旧文件没有 songKey/来源，这里按 v1 的老办法合成：本地路径进 local_scan，
  /// 否则按 URL 进 local_custom。返回 null 表示不是这种文件。
  static BackupDocument? decodeLegacyPlaylist(String content) {
    final Object? raw;
    try {
      raw = jsonDecode(content);
    } on FormatException {
      return null;
    }
    if (raw is! Map || raw['format'] != null || raw['songs'] is! List) {
      return null;
    }
    final songs = <BackupSong>[];
    for (final item in raw['songs'] as List) {
      if (item is! Map) continue;
      final title = (item['title'] as Object?)?.toString() ?? '';
      final artist = (item['artist'] as Object?)?.toString() ?? '';
      final url = (item['url'] as Object?)?.toString();
      final localPath = (item['localPath'] as Object?)?.toString();
      final source = (localPath != null && localPath.isNotEmpty)
          ? localPath
          : (url ?? '');
      if (source.isEmpty) continue;
      final isLocal = localPath != null && localPath.isNotEmpty;
      final id = 'imp_${_hash32(source)}';
      songs.add(BackupSong(
        songKey: (isLocal ? 'local_scan:' : 'local_custom:') + id,
        title: title,
        artist: artist,
        localPath: isLocal ? localPath : null,
      ));
    }
    if (songs.isEmpty) return null;
    final name = (raw['name'] as Object?)?.toString() ?? '导入的歌单';
    return BackupDocument(
      exportedAt: DateTime.fromMillisecondsSinceEpoch(0),
      playlists: <BackupPlaylist>[BackupPlaylist(name: name, songs: songs)],
    );
  }

  static Map<String, dynamic> _songToJson(BackupSong song) =>
      <String, dynamic>{
        'songKey': song.songKey,
        'title': song.title,
        'artist': song.artist,
        'duration': song.duration,
        'coverUrl': song.coverUrl,
        'localPath': song.localPath,
      };

  static BackupSong _songFromJson(Map<String, dynamic> json) => BackupSong(
        songKey: (json['songKey'] as Object?)?.toString() ?? '',
        title: (json['title'] as Object?)?.toString() ?? '',
        artist: (json['artist'] as Object?)?.toString() ?? '',
        duration: _asInt(json['duration']),
        coverUrl: (json['coverUrl'] as Object?)?.toString(),
        localPath: (json['localPath'] as Object?)?.toString(),
      );

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime _asDate(Object? value) {
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static List<Object?> _asList(Object? value) =>
      value is List ? value : const <Object?>[];

  /// 与 v1 PlaylistIo 一致的 32 位字符串哈希（只用于合成稳定 id）
  static int _hash32(String text) {
    var hash = 0;
    for (final code in text.codeUnits) {
      hash = (hash * 31 + code) & 0xFFFFFFFF;
    }
    return hash;
  }
}
