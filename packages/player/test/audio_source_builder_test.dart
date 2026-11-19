/// A11-M1：audioSourceBuilder 注入后必须被用于装载音源（默认仍是 AudioSource.uri）
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:player/player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('注入的 audioSourceBuilder 被调用', () async {
    Uri? seen;
    final player = PlayerImpl(
      audioSourceBuilder: (url) {
        seen = url;
        return AudioSource.uri(url);
      },
    );
    addTearDown(() async {
      try {
        await player.dispose();
      } catch (_) {}
    });

    final source = player.buildSource(Uri.parse('https://example.com/a.mp3'));
    expect(seen, Uri.parse('https://example.com/a.mp3'));
    expect(source, isA<UriAudioSource>());
  });
}
