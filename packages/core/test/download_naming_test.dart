import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('sanitizeFileNamePart', () {
    test('非法字符替换为 _ 并去首尾空格', () {
      expect(sanitizeFileNamePart('  a/b: c*? '), 'a_b_ c__');
    });
    test('空串返回空', () { expect(sanitizeFileNamePart('   '), ''); });
    test('超长截断到 120', () { expect(sanitizeFileNamePart('x' * 200).length, 120); });
  });

  group('buildDownloadFileName', () {
    test('默认歌手 - 歌曲', () {
      expect(buildDownloadFileName(title: '晴天', artist: '周杰伦'), '周杰伦 - 晴天.mp3');
    });
    test('歌曲 - 歌手顺序', () {
      expect(buildDownloadFileName(title: '晴天', artist: '周杰伦', order: 'title_artist'), '晴天 - 周杰伦.mp3');
    });
    test('无歌手只用歌名', () { expect(buildDownloadFileName(title: '晴天'), '晴天.mp3'); });
    test('空标题回退 untitled', () { expect(buildDownloadFileName(title: ' '), 'untitled.mp3'); });
  });

  group('uniqueFileName', () {
    test('不冲突直接返回', () { expect(uniqueFileName('a.mp3', {}), 'a.mp3'); });
    test('冲突追加 (2) (3)', () {
      expect(uniqueFileName('a.mp3', {'a.mp3'}), 'a (2).mp3');
      expect(uniqueFileName('a.mp3', {'a.mp3', 'a (2).mp3'}), 'a (3).mp3');
    });
  });

  group('detectAudioExtension', () {
    test('flac/ogg/id3/mp3 识别', () {
      expect(detectAudioExtension('fLaC'.codeUnits), 'flac');
      expect(detectAudioExtension('OggS'.codeUnits), 'ogg');
      expect(detectAudioExtension('ID3'.codeUnits), 'mp3');
      expect(detectAudioExtension([0xFF, 0xFB, 0x90, 0x00]), 'mp3');
    });
    test('无法识别返回 null', () { expect(detectAudioExtension('0000'.codeUnits), isNull); });
  });
}
