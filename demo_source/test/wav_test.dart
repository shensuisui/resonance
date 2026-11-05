import 'dart:typed_data';
import 'package:resonance_demo_source/wav.dart';
import 'package:test/test.dart';

void main() {
  test('生成标准 16kHz 单声道 16bit PCM WAV', () {
    final bytes = buildDemoWav(seconds: 1, sampleRate: 16000);
    final data = ByteData.sublistView(bytes);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(bytes.sublist(12, 16)), 'fmt ');
    expect(data.getUint16(20, Endian.little), 1); // PCM
    expect(data.getUint16(22, Endian.little), 1); // mono
    expect(data.getUint32(24, Endian.little), 16000);
    expect(data.getUint16(34, Endian.little), 16);
    expect(String.fromCharCodes(bytes.sublist(36, 40)), 'data');
    expect(bytes.length, 44 + 16000 * 2);
  });

  test('默认 30 秒音频足够播放器启动且不是全零静音', () {
    final bytes = buildDemoWav();
    expect(bytes.length, 44 + 16000 * 30 * 2);
    expect(bytes.sublist(44, 2000).any((b) => b != 0), isTrue);
  });
}
