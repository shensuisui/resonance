/// 基于 audiotags 的音频元数据读取器实现
///
/// audiotags 是 Flutter 插件（Rust FFI），支持 MP3/FLAC/M4A/AAC/OGG/OPUS 等
/// 全部主流格式的标签读写。不支持 Web（Web 浏览器有平台限制，功能阉割，
/// 按项目约定 Web 上本地音频标签读取跳过）。

import 'package:audiotags/audiotags.dart';
import 'package:core/core.dart';

class AudiotagsMetadataReader implements AudioMetadataReader {
  const AudiotagsMetadataReader();

  @override
  Future<AudioMetadata?> read(String filePath) async {
    try {
      final tag = await AudioTags.read(filePath);
      if (tag == null) return null;
      return AudioMetadata(
        title: tag.title,
        artist: tag.trackArtist ?? tag.albumArtist,
        album: tag.album,
        durationMs: tag.duration,
      );
    } on AudioTagsError {
      // 文件损坏或格式不支持时返回 null（上层退回文件名解析）
      return null;
    } catch (_) {
      return null;
    }
  }
}
