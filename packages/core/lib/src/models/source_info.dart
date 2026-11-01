import 'source_type.dart';

/// 音乐源信息
class SourceInfo {
  final String id;
  final String name;
  final String? iconUrl;
  final SourceType type;
  final bool enabled;

  /// 是否在「音乐库」页作为分栏展示
  ///
  /// 有的源只是数据聚合或来源（本地音乐、我最喜欢、6U音乐），
  /// 不该占据音乐库的分栏位置；由源自身声明，页面只做过滤。
  final bool showInLibrary;

  const SourceInfo({
    required this.id,
    required this.name,
    this.iconUrl,
    required this.type,
    this.enabled = true,
    this.showInLibrary = true,
  });

  SourceInfo copyWith({
    String? id,
    String? name,
    String? iconUrl,
    SourceType? type,
    bool? enabled,
    bool? showInLibrary,
  }) {
    return SourceInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      iconUrl: iconUrl ?? this.iconUrl,
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
      showInLibrary: showInLibrary ?? this.showInLibrary,
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