import 'dart:io';

import 'package:resonance_demo_source/demo_catalog.dart';
import 'package:test/test.dart';

/// 读取仓库内的真实演示数据；测试不构造另一份缩水 fixture，
/// 否则“数据迁移完整”这件事无法被验证。
Future<DemoCatalog> _loadCatalog() async {
  final root = Directory.current;
  return DemoCatalog.load(File('${root.path}/data/catalog.json'));
}

void main() {
  group('演示目录完整性', () {
    test('16 张专辑、190 首曲目、7 个歌单', () async {
      final catalog = await _loadCatalog();
      expect(catalog.albums, hasLength(16));
      expect(catalog.tracks, hasLength(190));
      expect(catalog.playlists, hasLength(7));
      expect(catalog.albums.map((a) => a.id), contains('midnights'));
      expect(catalog.tracks.map((t) => t.id), contains('midnights-3'));
    });

    test('旧配表里的导入/下载/来源归属都被保留', () async {
      final catalog = await _loadCatalog();
      final kindOfBlue = catalog.track('kind-of-blue#1')!;
      expect(kindOfBlue.local, isTrue);
      final midnight = catalog.track('midnights-3')!;
      expect(midnight.downloaded, isTrue);
      expect(midnight.sourceId, 'fy');
      expect(catalog.track('nevermind-11')!.local, isTrue);
    });

    test('时长算法与旧实现一致', () {
      expect(DemoCatalog.makeDuration('midnights#3'), 253);
      expect(DemoCatalog.makeDuration('abbey-road#7'), 324);
    });
  });

  group('搜索与歌单', () {
    test('空关键词返回空，不伪造全量结果', () async {
      final catalog = await _loadCatalog();
      expect(catalog.search('', page: 1, pageSize: 20), isEmpty);
      expect(catalog.search('   ', page: 1, pageSize: 20), isEmpty);
    });

    test('歌名、艺人、专辑、流派都能命中', () async {
      final catalog = await _loadCatalog();
      expect(catalog.search('blue', page: 1, pageSize: 100), isNotEmpty);
      expect(catalog.search('Taylor', page: 1, pageSize: 100), isNotEmpty);
      expect(catalog.search('Abbey Road', page: 1, pageSize: 100), isNotEmpty);
      expect(catalog.search('爵士', page: 1, pageSize: 100), isNotEmpty);
    });

    test('分页切片稳定', () async {
      final catalog = await _loadCatalog();
      final all = catalog.search('a', page: 1, pageSize: 1000);
      final first = catalog.search('a', page: 1, pageSize: 5);
      final second = catalog.search('a', page: 2, pageSize: 5);
      expect(first, all.take(5).toList());
      expect(second, all.skip(5).take(5).toList());
    });

    test('歌单按引用顺序解析曲目', () async {
      final catalog = await _loadCatalog();
      final playlist = catalog.playlist('pl-night-drive')!;
      expect(playlist.name, '深夜公路');
      expect(catalog.resolve(playlist.refs), hasLength(8));
      expect(catalog.resolve(playlist.refs).first.id, 'random-access-memories-8');
    });
  });

  test('每首歌词都有非空行且键对应真实曲目', () async {
    final catalog = await _loadCatalog();
    final lyrics = await DemoCatalog.loadLyrics(File('${Directory.current.path}/data/lyrics.json'));
    expect(lyrics, hasLength(9));
    for (final entry in lyrics.entries) {
      expect(catalog.track(entry.key), isNotNull, reason: entry.key);
      expect(entry.value.where((line) => line.isNotEmpty), isNotEmpty);
    }
  });
}
