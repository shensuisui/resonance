/// 艺术家模型
class Artist {
  final String id;
  final String sourceId;
  final String name;
  final String? avatar;
  final String? description;
  final Map<String, dynamic> extra;

  const Artist({
    required this.id,
    required this.sourceId,
    required this.name,
    this.avatar,
    this.description,
    this.extra = const {},
  });

  Artist copyWith({
    String? id,
    String? sourceId,
    String? name,
    String? avatar,
    String? description,
    Map<String, dynamic>? extra,
  }) {
    return Artist(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      description: description ?? this.description,
      extra: extra ?? this.extra,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Artist && id == other.id && sourceId == other.sourceId;

  @override
  int get hashCode => Object.hash(id, sourceId);

  @override
  String toString() => 'Artist(id: $id, name: $name)';
}