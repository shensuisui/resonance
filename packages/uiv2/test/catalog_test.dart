/// Catalog 元数据解析测试（lib/src/data/catalog.dart）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/data/catalog.dart';

Map<String, dynamic> fixture() => {
      'albums': [
        {
          'id': 'a1',
          'title': 'Album One',
          'artist': 'Zed',
          'year': 2001,
          'genre': 'Rock',
          'cover': 'http://demo/covers/a1.jpg',
          'imported': true,
          'downloaded': false,
          'tracks': ['a1#1', 'a1#2'],
        },
        {
          'id': 'b1',
          'title': 'Album Two',
          'artist': 'Alice',
          'year': 2002,
          'genre': 'Jazz',
          'cover': 'http://demo/covers/b1.jpg',
          'imported': false,
          'downloaded': true,
          'tracks': ['b1#1'],
        },
      ],
      'tracks': [
        {'id':'a1#1','no':1,'title':'First','artist':'Zed','albumId':'a1','album':'Album One','cover':'http://demo/covers/a1.jpg','genre':'Rock','duration':201,'local':true,'downloaded':false,'sourceId':'fy'},
        {'id':'a1#2','no':2,'title':'Second','artist':'Zed','albumId':'a1','album':'Album One','cover':'http://demo/covers/a1.jpg','genre':'Rock','duration':202,'local':true,'downloaded':false,'sourceId':'fy'},
        {'id':'b1#1','no':1,'title':'Third','artist':'Alice','albumId':'b1','album':'Album Two','cover':'http://demo/covers/b1.jpg','genre':'Jazz','duration':203,'local':false,'downloaded':true,'sourceId':'yu7'},
      ],
    };

void main() {
  group('Catalog.fromJson', () {
    final catalog = Catalog.fromJson(fixture());
    test('曲目与专辑交叉引用完整', () {
      expect(catalog.tracks, hasLength(3));
      expect(catalog.albums, hasLength(2));
      expect(catalog.album('a1')!.tracks.map((t) => t.id), ['a1#1', 'a1#2']);
      expect(catalog.track('b1#1')!.downloaded, isTrue);
      expect(catalog.track('missing'), isNull);
    });
    test('艺人按名字排序并聚合曲目', () {
      expect(catalog.artists.map((a) => a.name), ['Alice', 'Zed']);
      expect(catalog.artists.last.tracks, hasLength(2));
    });
    test('resolve 保持引用顺序并跳过坏引用', () {
      expect(catalog.resolve(['a1#2', 'bad', 'b1#1']).map((t) => t.id), ['a1#2', 'b1#1']);
    });
  });
  test('Catalog.empty 是正常空目录', () {
    final empty = Catalog.empty();
    expect(empty.albums, isEmpty);
    expect(empty.tracks, isEmpty);
    expect(empty.artists, isEmpty);
    expect(empty.track('x'), isNull);
  });
  group('formatDuration', () {
    test('m:ss 边界', () {
      expect(formatDuration(0), '0:00');
      expect(formatDuration(59), '0:59');
      expect(formatDuration(60), '1:00');
      expect(formatDuration(125), '2:05');
      expect(formatDuration(-3), '0:00');
    });
    test('中文长描述', () {
      expect(formatDurationLong(30), '1 分钟');
      expect(formatDurationLong(45 * 60), '45 分钟');
      expect(formatDurationLong(3661), '1 小时 1 分');
      expect(formatDurationLong(7200), '2 小时 0 分');
    });
    test('hashStr 稳定、非负、空串为 0', () {
      expect(hashStr('abc'), hashStr('abc'));
      expect(hashStr('abc'), isNonNegative);
      expect(hashStr(''), 0);
    });
  });
}
