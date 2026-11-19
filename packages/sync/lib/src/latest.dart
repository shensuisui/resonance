/// latest.json：云端「最新版本指针」
///
/// 只含版本号/文件名/校验和/设备列表，体积很小；
/// 先读它判断要不要下载快照，省流量。
library;

import 'dart:convert';

/// 设备条目（出现在 latest.json.devices）
class LatestDevice {
  /// 设备 id（UUID）
  final String id;

  /// 设备名（默认主机名/机型）
  final String name;

  /// 最后见到时间（毫秒，UTC）
  final int lastSeenAt;

  /// 构造
  const LatestDevice({
    required this.id,
    required this.name,
    required this.lastSeenAt,
  });

  /// 转 JSON
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'lastSeenAt': lastSeenAt,
      };

  /// 从 JSON 还原
  factory LatestDevice.fromJson(Map<String, Object?> json) => LatestDevice(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        lastSeenAt: (json['lastSeenAt'] as num?)?.toInt() ?? 0,
      );
}

/// 一份历史版本的元信息（供历史版本明细展示）
class LatestVersionInfo {
  /// 版本号
  final int version;

  /// 快照相对路径
  final String file;

  /// 校验和
  final String sha256;

  /// 推送设备 id
  final String writer;

  /// 推送来源（manual / auto）
  final String trigger;

  /// 推送时间（毫秒，UTC）
  final int updatedAt;

  /// 构造
  const LatestVersionInfo({
    required this.version,
    required this.file,
    required this.sha256,
    required this.writer,
    this.trigger = 'auto',
    required this.updatedAt,
  });

  /// 转 JSON
  Map<String, Object?> toJson() => <String, Object?>{
        'version': version,
        'file': file,
        'sha256': sha256,
        'writer': writer,
        'trigger': trigger,
        'updatedAt': updatedAt,
      };

  /// 从 JSON 还原
  factory LatestVersionInfo.fromJson(Map<String, Object?> json) =>
      LatestVersionInfo(
        version: (json['version'] as num?)?.toInt() ?? 0,
        file: json['file'] as String? ?? '',
        sha256: json['sha256'] as String? ?? '',
        writer: json['writer'] as String? ?? '',
        trigger: json['trigger'] as String? ?? 'auto',
        updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

/// 最新版本指针
class LatestDoc {
  /// 快照版本号
  final int version;

  /// 快照相对路径（如 snapshots/v0042.tar.bz2）
  final String file;

  /// 快照字节的 sha256
  final String sha256;

  /// 写入时间（毫秒，UTC）
  final int updatedAt;

  /// 最后写入设备
  final String writer;

  /// 推送来源（manual=手动 / auto=自动，供历史版本明细展示）
  final String trigger;

  /// 已知设备列表
  final List<LatestDevice> devices;

  /// 最近若干版本的元信息（最多 7 条，供历史明细）
  final List<LatestVersionInfo> history;

  /// 构造
  const LatestDoc({
    required this.version,
    required this.file,
    required this.sha256,
    required this.updatedAt,
    required this.writer,
    this.trigger = 'auto',
    this.devices = const <LatestDevice>[],
    this.history = const <LatestVersionInfo>[],
  });

  /// 魔数
  static const String magic = 'resonance-sync-latest';

  /// 结构版本
  static const int schema = 1;

  /// 转 JSON 字符串（便于直接上传）
  String encode() => jsonEncode(<String, Object?>{
        'format': magic,
        'schema': schema,
        'version': version,
        'file': file,
        'sha256': sha256,
        'updatedAt': updatedAt,
        'writer': writer,
        'trigger': trigger,
        'devices': <Object?>[for (final d in devices) d.toJson()],
        'history': <Object?>[for (final h in history) h.toJson()],
      });

  /// 从 JSON Map 还原（trigger 为可选字段，缺省按 auto 兼容旧快照）
  factory LatestDoc.fromJson(Map<String, Object?> json) {
    if (json['format'] != magic) {
      throw const FormatException('不是 resonance-sync-latest');
    }
    final schemaValue = (json['schema'] as num?)?.toInt() ?? 0;
    if (schemaValue > schema) {
      throw FormatException('latest 版本过高：$schemaValue');
    }
    final list = (json['devices'] as List?) ?? const <Object?>[];
    return LatestDoc(
      version: (json['version'] as num?)?.toInt() ?? 0,
      file: json['file'] as String? ?? '',
      sha256: json['sha256'] as String? ?? '',
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      writer: json['writer'] as String? ?? '',
      trigger: json['trigger'] as String? ?? 'auto',
      history: <LatestVersionInfo>[
        for (final item in (json['history'] as List?) ?? const <Object?>[])
          LatestVersionInfo.fromJson((item as Map).cast<String, Object?>()),
      ],
      devices: <LatestDevice>[
        for (final item in list)
          LatestDevice.fromJson((item as Map).cast<String, Object?>()),
      ],
    );
  }

  /// 从 JSON 字符串还原（损坏时抛 FormatException）
  factory LatestDoc.decode(String text) =>
      LatestDoc.fromJson(jsonDecode(text) as Map<String, Object?>);

  /// 合并设备列表（同一设备取最后见到时间较新者）
  LatestDoc withDevice(LatestDevice me) {
    final merged = <String, LatestDevice>{
      for (final d in devices) d.id: d,
    };
    final existing = merged[me.id];
    if (existing == null || me.lastSeenAt >= existing.lastSeenAt) {
      merged[me.id] = me;
    }
    return LatestDoc(
      version: version,
      file: file,
      sha256: sha256,
      updatedAt: updatedAt,
      writer: writer,
      trigger: trigger,
      history: history,
      devices: merged.values.toList(),
    );
  }
}
