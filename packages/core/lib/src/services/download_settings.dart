/// 下载设置键（settings 表 key-value）
abstract final class DownloadSettingsKeys {
  /// 命名顺序：artist_title（默认）/ title_artist
  static const String nameOrder = 'download_name_order';

  /// 封面缩略图边长（像素），默认 256
  static const String coverSize = 'download_cover_size';

  /// 封面 JPEG 质量，默认 85
  static const String coverQuality = 'download_cover_quality';
}
