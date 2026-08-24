import 'source_type.dart';

/// 音乐源信息
class SourceInfo {
  final String id;
  final String name;
  final String? iconUrl;
  final SourceType type;
  final bool enabled;

  const SourceInfo({
    required this.id,
    required this.name,
    this.iconUrl,
    required this.type,
    this.enabled = true,
  });

  SourceInfo copyWith({
    String? id,
    String? name,
    String? iconUrl,
    SourceType? type,
    bool? enabled,
  }) {
    return SourceInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      iconUrl: iconUrl ?? this.iconUrl,
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceInfo && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SourceInfo(id: $id, name: $name, type: $type)';
}