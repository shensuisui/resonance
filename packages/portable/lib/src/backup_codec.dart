/// 备份编解码：v2 记录式 JSON（魔数 resonance-backup）+ v1 兼容
library;

import 'dart:convert';

import 'backup_model.dart';
import 'snapshot.dart';

/// 歌单 id 推导（与历史导入保持一致，保证 v1 导入结果稳定）
String legacyPlaylistIdForName(String name) {
  var hash = 0;
  for (final code in name.codeUnits) {
    hash = (hash * 31 + code) & 0x7FFFFFFF;
  }
  return 'import_${hash.toRadixString(16)}';
}

/// 编解码
abstract final class BackupCodec {
  /// 魔数
  static const String magic = 'resonance-backup';

  /// 当前结构版本
  static const int currentVersion = 2;

  /// 编码为 JSON 文本
  static String encode(BackupDocument doc) {
    final entities = <String, Object?>{};
    doc.entities.forEach((key, list) {
      entities[key] = <Object?>[for (final r in list) r.toJson()];
    });
    return jsonEncode(<String, Object?>{
      'format': magic,
      'version': currentVersion,
      'exportedAt': doc.exportedAt.toUtc().toIso8601String(),
      'deviceId': doc.deviceId,
      'assets': <Object?>[for (final a in doc.assets) a.toJson()],
      'entities': entities,
    });
  }

  /// 解码（v1 自动升级为记录式）
  static BackupDocument decode(String text) {
    final Map<String, Object?> map;
    try {
      final raw = jsonDecode(text);
      if (raw is! Map) throw const FormatException();
      map = raw.cast<String, Object?>();
    } on Object {
      throw const BackupException('不是有效的备份文件');
    }
    if (map['format'] != magic) {
      throw const BackupException('不是 resonance 备份文件');
    }
    final version = (map['version'] as num?)?.toInt() ?? 0;
    if (version > currentVersion) {
      throw BackupException('备份版本过高（$version），请升级 App');
    }
    final exportedAt = _parseDate(map['exportedAt']) ?? DateTime.now();
    if (version <= 1) return _fromV1(map, exportedAt);

    final entities = <String, List<SyncRecord>>{};
    final rawEntities =
        (map['entities'] as Map?)?.cast<String, Object?>() ?? const {};
    rawEntities.forEach((key, value) {
      if (value is! List) return;
      entities[key] = <SyncRecord>[
        for (final item in value)
          SyncRecord.fromJson((item as Map).cast<String, Object?>()),
      ];
    });
    return BackupDocument(
      version: 2,
      exportedAt: exportedAt,
      deviceId: (map['deviceId'] as String?) ?? 'unknown',
      entities: entities,
      assets: <AssetEntry>[
        for (final a in (map['assets'] as List?) ?? const <Object?>[])
          AssetEntry.fromJson((a as Map).cast<String, Object?>()),
      ],
    );
  }

  /// 单歌单导出（仍走 v2 记录式，歌单按 legacy id 命名）
  static BackupDocument singlePlaylist({
    required String name,
    required List<Map<String, Object?>> songs,
    DateTime? now,
  }) {
    final songKeys = <String>[];
    final snapshots = <String, Object?>{};
    for (final s in songs) {
      var key = (s['songKey'] as String?) ?? '';
      if (key.isEmpty) {
        // 旧版单歌单可能只有 title/url：给一个稳定的本地键，保证可导入
        key = 'local_custom:${songKeys.length}';
      }
      if (songKeys.contains(key)) continue;
      songKeys.add(key);
      snapshots[key] = <String, Object?>{
        'title': s['title'],
        'artist': s['artist'],
        'coverUrl': s['coverUrl'],
        'duration': s['duration'],
      };
    }
    final updatedAt = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return BackupDocument(
      exportedAt: now ?? DateTime.now(),
      deviceId: 'export',
      entities: <String, List<SyncRecord>>{
        SyncEntity.playlists: <SyncRecord>[
          SyncRecord(
            key: legacyPlaylistIdForName(name),
            updatedAt: updatedAt,
            deviceId: 'export',
            data: <String, Object?>{
              'id': legacyPlaylistIdForName(name),
              'name': name,
              'songKeys': songKeys,
              'snapshots': snapshots,
            },
          ),
        ],
      },
    );
  }

  /// 解旧版「单歌单 JSON」（{name,songs[]} 或 songs[]），非该形态返回 null
  static BackupDocument? decodeLegacyPlaylist(String text) {
    try {
      final raw = jsonDecode(text);
      String name = '导入的歌单';
      List<Object?> songs = const <Object?>[];
      if (raw is Map) {
        name = (raw['name'] as String?) ?? (raw['title'] as String?) ?? name;
        songs = (raw['songs'] as List?) ?? const <Object?>[];
      } else if (raw is List) {
        songs = raw;
      } else {
        return null;
      }
      final maps = <Map<String, Object?>>[];
      for (final s in songs) {
        if (s is! Map) continue;
        maps.add(s.cast<String, Object?>());
      }
      if (maps.isEmpty) return null;
      return singlePlaylist(name: name, songs: maps);
    } on Object {
      return null;
    }
  }

  static BackupDocument _fromV1(Map<String, Object?> map, DateTime exportedAt) {
    final at = exportedAt.millisecondsSinceEpoch;
    final entities = <String, List<SyncRecord>>{};

    final playlists = <SyncRecord>[];
    for (final p in (map['playlists'] as List?) ?? const <Object?>[]) {
      if (p is! Map) continue;
      final pm = p.cast<String, Object?>();
      final name = (pm['name'] as String?) ?? '导入的歌单';
      final id = legacyPlaylistIdForName(name);
      final songKeys = <String>[];
      final snapshots = <String, Object?>{};
      for (final s in (pm['songs'] as List?) ?? const <Object?>[]) {
        if (s is! Map) continue;
        final sm = s.cast<String, Object?>();
        final key = (sm['songKey'] as String?) ?? '';
        if (key.isEmpty || songKeys.contains(key)) continue;
        songKeys.add(key);
        snapshots[key] = <String, Object?>{
          'title': sm['title'],
          'artist': sm['artist'],
          'coverUrl': sm['coverUrl'],
          'duration': sm['duration'],
        };
      }
      playlists.add(SyncRecord(
        key: id,
        updatedAt: at,
        deviceId: 'legacy',
        data: <String, Object?>{
          'id': id,
          'name': name,
          'songKeys': songKeys,
          'snapshots': snapshots,
        },
      ));
    }
    if (playlists.isNotEmpty) entities[SyncEntity.playlists] = playlists;

    final favorites = <SyncRecord>[];
    for (final f in (map['favorites'] as List?) ?? const <Object?>[]) {
      if (f is! Map) continue;
      final fm = f.cast<String, Object?>();
      final key = (fm['songKey'] as String?) ?? '';
      if (key.isEmpty) continue;
      final time = (fm['time'] as num?)?.toInt() ?? at;
      favorites.add(SyncRecord(
        key: key,
        updatedAt: time,
        deviceId: 'legacy',
        data: <String, Object?>{
          'songKey': key,
          'time': time,
          'title': fm['title'],
          'artist': fm['artist'],
          'coverUrl': fm['coverUrl'],
        },
      ));
    }
    if (favorites.isNotEmpty) entities[SyncEntity.favorites] = favorites;

    final recent = <SyncRecord>[];
    for (final r in (map['recent'] as List?) ?? const <Object?>[]) {
      if (r is! Map) continue;
      final rm = r.cast<String, Object?>();
      final key = (rm['songKey'] as String?) ?? '';
      if (key.isEmpty) continue;
      final playedAt = (rm['playedAt'] as num?)?.toInt() ?? at;
      recent.add(SyncRecord(
        key: key,
        updatedAt: playedAt,
        deviceId: 'legacy',
        data: <String, Object?>{
          'songKey': key,
          'playedAt': playedAt,
          'title': rm['title'],
          'artist': rm['artist'],
          'coverUrl': rm['coverUrl'],
        },
      ));
    }
    if (recent.isNotEmpty) entities[SyncEntity.recent] = recent;

    final progress = <SyncRecord>[];
    for (final p in (map['progress'] as List?) ?? const <Object?>[]) {
      if (p is! Map) continue;
      final pm = p.cast<String, Object?>();
      final kind = (pm['queueKind'] as String?) ?? '';
      final id = (pm['queueId'] as String?) ?? '';
      final key = '$kind|$id';
      progress.add(SyncRecord(
        key: key,
        updatedAt: (pm['updatedAt'] as num?)?.toInt() ?? at,
        deviceId: 'legacy',
        data: <String, Object?>{
          'queueKind': kind,
          'queueId': id,
          'songKey': (pm['songKey'] as String?) ?? '',
          'positionMs': (pm['positionMs'] as num?)?.toInt() ?? 0,
          'updatedAt': (pm['updatedAt'] as num?)?.toInt() ?? at,
        },
      ));
    }
    if (progress.isNotEmpty) entities[SyncEntity.progress] = progress;

    final settings = <SyncRecord>[];
    final rawSettings = (map['settings'] as Map?)?.cast<String, Object?>() ?? const {};
    rawSettings.forEach((key, value) {
      settings.add(SyncRecord(
        key: key,
        updatedAt: at,
        deviceId: 'legacy',
        data: <String, Object?>{'key': key, 'value': '${value ?? ''}'},
      ));
    });
    if (settings.isNotEmpty) entities[SyncEntity.settings] = settings;

    return BackupDocument(
      version: 2,
      exportedAt: exportedAt,
      deviceId: 'legacy',
      entities: entities,
    );
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }
}
