import 'dart:math' as math;
import 'dart:typed_data';

/// 生成一段可播放的 PCM WAV。
///
/// 默认 16kHz / 单声道 / 16-bit / 30 秒。音频不是静音：用很低的音量叠加
/// 220Hz、329.63Hz、440Hz 三个正弦波，并做淡入淡出，既能证明播放器真实出声，
/// 又不会在调试时过于刺耳。完全由代码生成，不提交二进制、不依赖 ffmpeg。
Uint8List buildDemoWav({int seconds = 30, int sampleRate = 16000}) {
  if (seconds <= 0 || sampleRate <= 0) {
    throw ArgumentError('seconds 和 sampleRate 必须为正数');
  }
  const channels = 1;
  const bitsPerSample = 16;
  const bytesPerSample = bitsPerSample ~/ 8;
  final sampleCount = sampleRate * seconds;
  final dataLength = sampleCount * channels * bytesPerSample;
  final bytes = Uint8List(44 + dataLength);
  final data = ByteData.sublistView(bytes);

  void writeAscii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  writeAscii(0, 'RIFF');
  data.setUint32(4, 36 + dataLength, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * channels * bytesPerSample, Endian.little);
  data.setUint16(32, channels * bytesPerSample, Endian.little);
  data.setUint16(34, bitsPerSample, Endian.little);
  writeAscii(36, 'data');
  data.setUint32(40, dataLength, Endian.little);

  const fadeSeconds = 0.5;
  for (var i = 0; i < sampleCount; i++) {
    final t = i / sampleRate;
    final fadeIn = (t / fadeSeconds).clamp(0.0, 1.0);
    final fadeOut = ((seconds - t) / fadeSeconds).clamp(0.0, 1.0);
    final envelope = math.min(fadeIn, fadeOut);
    final value = 0.055 * math.sin(2 * math.pi * 220 * t) +
        0.035 * math.sin(2 * math.pi * 329.63 * t) +
        0.015 * math.sin(2 * math.pi * 440 * t);
    final sample = (value * envelope * 32767).round().clamp(-32768, 32767);
    data.setInt16(44 + i * 2, sample, Endian.little);
  }
  return bytes;
}
