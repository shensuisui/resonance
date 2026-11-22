/// 可移植设置键白名单（云同步与备份共用）
///
/// 依据 docs/features/webdav-sync.md §5.4：
///   * 设备本地项不参与（scan_dir、play_device、sync_*）；
///   * 偏好类（主题/播放模式/音量/搜索历史/封面与命名偏好等）参与；
///   * 源开关按前缀 source_enabled_ 参与。
abstract final class PortableSettingsKeys {
  /// 精确匹配的设置键
  static const Set<String> keys = <String>{
    'theme_mode',
    'play_mode',
    'volume',
    'wifi_only',
    'search_history',
    'audio_cache_play',
    'lyrics_open',
    'corner_radius',
    'seed_color',
    'last_queue',
    'download_name_order',
    'download_cover_size',
    'download_cover_quality',
  };

  /// 设备本地键（不参与云同步；备份中作为可选分区）
  static const Set<String> deviceLocalKeys = <String>{
    'scan_dir',
    'play_device',
  };

  /// 前缀匹配（每个源一个开关）
  static const List<String> prefixes = <String>['source_enabled_'];

  /// 该键是否参与同步
  static bool isSyncable(String key) =>
      keys.contains(key) || prefixes.any(key.startsWith);
}
