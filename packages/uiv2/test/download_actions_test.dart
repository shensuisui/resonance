/// P4a：下载入口必须先解析播放地址（带 referer/UA），并补齐歌词
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/providers/providers.dart';

class _FakeDownloadManager implements DownloadManager {
  String? url;
  Map<String, String>? headers;
  String? lyrics;

  @override
  Future<String?> download(
    Song song, {
    String? url,
    Map<String, String>? headers,
    String? lyrics,
  }) async {
    this.url = url;
    this.headers = headers;
    this.lyrics = lyrics;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSourceManager extends SourceManager {
  @override
  Map<String, String> playHeadersFor(String sourceId) =>
      {'referer': 'https://ref.example/'};

  @override
  Future<PlayableInfo> getPlayable(String sourceId, String songId,
          {String? captchaCode, String? captchaKey}) async =>
      const PlayableInfo(url: 'https://cdn.example/a.mp3');
}

void main() {
  test('列表 Song 无 playUrl 时也能解析出地址', () async {
    final dm = _FakeDownloadManager();
    final container = ProviderContainer(overrides: [
      downloadManagerProvider.overrideWithValue(dm),
      sourceManagerProvider.overrideWithValue(_FakeSourceManager()),
    ]);
    addTearDown(container.dispose);

    final song = Song(
      id: '1',
      sourceId: 's',
      title: '歌',
      artist: '手',
      lyric: '[00:01.00]已有词',
    );
    await container.read(downloadActionsProvider).download(song);

    expect(dm.url, 'https://cdn.example/a.mp3');
    expect(dm.headers!['referer'], 'https://ref.example/');
    expect(dm.lyrics, '[00:01.00]已有词');
  });

  test('已下载的歌不再解析地址', () async {
    final dm = _FakeDownloadManager();
    final container = ProviderContainer(overrides: [
      downloadManagerProvider.overrideWithValue(dm),
      sourceManagerProvider.overrideWithValue(_FakeSourceManager()),
    ]);
    addTearDown(container.dispose);

    final song = Song(
      id: '2',
      sourceId: 's',
      title: '歌',
      artist: '手',
      localPath: '/tmp/x.mp3',
    );
    await container.read(downloadActionsProvider).download(song);
    expect(dm.url, isNull);
  });
}
