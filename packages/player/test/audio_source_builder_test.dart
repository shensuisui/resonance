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
      audioSourceBuilder: (url, {Song? song}) {
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
    // 传 song 时 builder 应收到（用于缓存键/源请求头）
    const s = Song(id: '1', sourceId: 's', title: 't', artist: 'a');
    player.buildSource(Uri.parse('https://example.com/a.mp3'), song: s);
    expect(seen, Uri.parse('https://example.com/a.mp3'));
    expect(source, isA<UriAudioSource>());
  });
}
