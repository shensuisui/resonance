/// 音频元数据
///
/// 从本地音频文件读取的元数据标签（ID3/FLAC 等）。
/// 纯 Dart 模型，跨包共享。
class AudioMetadata {
  final String? title;
  final String? artist;
  final String? album;
  final int? durationMs;

  const AudioMetadata({
    this.title,
    this.artist,
    this.album,
    this.durationMs,
  });
}

/// 音频元数据读取器抽象接口
///
/// core 为纯 Dart 包，无法直接依赖 Flutter 插件（如 audiotags）。
/// 具体实现下沉到 Flutter 层（如 db 包），通过依赖注入传入。
/// 未来如需支持 Web，只需替换实现，接口不变。
abstract class AudioMetadataReader {
  /// 读取音频文件元数据。文件不存在或无标签时返回 null。
  Future<AudioMetadata?> read(String filePath);
}
