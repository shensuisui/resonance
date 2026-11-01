/// Catalog 单元测试（lib/src/data/catalog.dart）。
///
/// 测什么：
///   * [Catalog.build] 派生表：专辑数、曲目总数（各专辑 tracks 之和）、艺人排序；
///   * [makeDuration]：同一 id 稳定、范围 148~361；
///   * [formatDuration] / [formatDurationLong]：0/59/60/3661 等边界；
///   * [CatalogTrack.sourceId] 归属：SOURCE_BY_TRACK 单曲覆盖优先于 SOURCE_BY_ALBUM；
///   * local/downloaded 标记：kImportedAlbumIds 专辑 local=true、
///     kImportedExtraTrackIds 单曲 local=true、kDownloadedAlbumIds downloaded=true。
///
/// 模拟数据来源：全部使用包内配表常量（kAlbumSeeds / kSourceByAlbum /
/// kSourceByTrack / kImportedAlbumIds / kImportedExtraTrackIds /
/// kDownloadedAlbumIds），不引入任何外部 mock。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/data/catalog.dart';

void main() {
  group('Catalog.build 派生表', () {
    final catalog = Catalog.build();

    test('专辑数量等于配表数量（16 张）', () {
      expect(catalog.albums.length, kAlbumSeeds.length);
      expect(catalog.albums.length, 16);
    });

    test('曲目总数 = 各专辑 tracks 之和，且按专辑顺序铺平', () {
      final expectedTotal =
          kAlbumSeeds.fold<int>(0, (sum, a) => sum + a.tracks.length);
      expect(catalog.tracks.length, expectedTotal);
      for (var i = 0; i < kAlbumSeeds.length; i++) {
        expect(catalog.albums[i].tracks.length, kAlbumSeeds[i].tracks.length);
      }
      // 铺平顺序：按专辑顺序、专辑内按曲目号顺序
      expect(catalog.tracks.first.id, 'abbey-road#1');
      expect(catalog.tracks.last.id, 'blue#${kAlbumSeeds.last.tracks.length}');
    });

    test('曲目 id 形如 <albumId>#<no>，no 从 1 起连续', () {
      for (final album in catalog.albums) {
        for (var i = 0; i < album.tracks.length; i++) {
          expect(album.tracks[i].id, '${album.id}#${i + 1}');
          expect(album.tracks[i].no, i + 1);
        }
      }
    });

    test('track/album 按 id 查询、resolve 解析引用', () {
      expect(catalog.track('midnights#3')!.title, 'Anti-Hero');
      expect(catalog.album('kind-of-blue')!.title, 'Kind of Blue');
      expect(catalog.track('不存在#1'), isNull);
      expect(catalog.album('不存在'), isNull);

      final resolved = catalog.resolve(['midnights#3', '坏引用', 'blonde#7']);
      expect(resolved.map((t) => t.id).toList(), ['midnights#3', 'blonde#7']);
    });

    test('艺人按名字排序（不区分大小写），曲目按艺人聚合', () {
      final names = catalog.artists.map((a) => a.name).toList();
      final sorted = List.of(names)
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      expect(names, sorted);

      // 每位艺人的曲目数 = 其全部专辑曲目数之和
      for (final artist in catalog.artists) {
        final sum = artist.albums.fold<int>(0, (s, a) => s + a.tracks.length);
        expect(artist.tracks.length, sum);
        for (final album in artist.albums) {
          expect(album.artist, artist.name);
        }
      }
      expect(names.toSet().length, names.length);
    });

    test('displayNo 返回 index+1', () {
      final track = catalog.track('abbey-road#7')!;
      expect(catalog.displayNo(track, 0), 1);
      expect(catalog.displayNo(track, 9), 10);
    });
  });

  group('makeDuration / hashStr', () {
    test('同一 id 结果稳定', () {
      final a = makeDuration('midnights#3');
      final b = makeDuration('midnights#3');
      expect(a, b);
    });

    test('范围 148~361', () {
      for (final album in kAlbumSeeds) {
        for (var i = 1; i <= album.tracks.length; i++) {
          final d = makeDuration('${album.id}#$i');
          expect(d, inInclusiveRange(148, 361),
              reason: '${album.id}#$i -> $d');
        }
      }
    });

    test('不同 id 大概率得到不同时长（抽样若干）', () {
      final ids = [
        'abbey-road#1',
        'blonde#2',
        'ok-computer#3',
        'damn#4',
        'blue#5',
        'nevermind#6',
      ];
      final durations = ids.map(makeDuration).toSet();
      expect(durations.length, greaterThan(1));
    });

    test('hashStr 稳定且非负', () {
      expect(hashStr('abc'), hashStr('abc'));
      expect(hashStr('abc'), isNonNegative);
      expect(hashStr(''), 0);
    });
  });

  group('formatDuration（秒 -> m:ss）', () {
    test('0 秒边界', () => expect(formatDuration(0), '0:00'));
    test('59 秒边界', () => expect(formatDuration(59), '0:59'));
    test('60 秒边界', () => expect(formatDuration(60), '1:00'));
    test('个位补零', () => expect(formatDuration(125), '2:05'));
    test('负数按 0 处理', () => expect(formatDuration(-3), '0:00'));
  });

  group('formatDurationLong（秒 -> 中文长描述）', () {
    test('不足 1 分钟（30 秒 -> 1 分钟，四舍五入）', () {
      expect(formatDurationLong(30), '1 分钟');
    });
    test('45 分钟', () => expect(formatDurationLong(45 * 60), '45 分钟'));
    test('3661 秒 -> 1 小时 1 分', () {
      expect(formatDurationLong(3661), '1 小时 1 分');
    });
    test('7200 秒 -> 2 小时 0 分', () {
      expect(formatDurationLong(7200), '2 小时 0 分');
    });
  });

  group('CatalogTrack.sourceId 归属', () {
    final catalog = Catalog.build();

    test('单曲覆盖表（SOURCE_BY_TRACK）优先于专辑归属', () {
      for (final entry in kSourceByTrack.entries) {
        final track = catalog.track(entry.key);
        expect(track, isNotNull, reason: '覆盖表里的 id 必须存在');
        expect(track!.sourceId, entry.value,
            reason: '${entry.key} 应被单曲覆盖表命中为 ${entry.value}');
      }
    });

    test('未覆盖的曲目按专辑归属（SOURCE_BY_ALBUM）', () {
      for (final album in catalog.albums) {
        for (final track in album.tracks) {
          if (kSourceByTrack.containsKey(track.id)) continue;
          expect(track.sourceId, kSourceByAlbum[album.id] ?? 'local',
              reason: '${track.id} 应按专辑归属 ${kSourceByAlbum[album.id]}');
        }
      }
    });

    test('专辑归属配表覆盖所有 16 张专辑', () {
      expect(kSourceByAlbum.keys.length, kAlbumSeeds.length);
    });
  });

  group('local / downloaded 标记', () {
    final catalog = Catalog.build();

    test('本地导入专辑内的曲目 local=true', () {
      for (final albumId in kImportedAlbumIds) {
        for (final track in catalog.album(albumId)!.tracks) {
          expect(track.local, isTrue, reason: '${track.id} 应为本地曲目');
        }
        expect(catalog.album(albumId)!.imported, isTrue);
      }
    });

    test('本地导入单曲（kImportedExtraTrackIds）local=true', () {
      for (final id in kImportedExtraTrackIds) {
        expect(catalog.track(id)!.local, isTrue, reason: '$id 应为本地单曲');
      }
    });

    test('非导入专辑的其余曲目 local=false', () {
      for (final album in catalog.albums) {
        if (kImportedAlbumIds.contains(album.id)) continue;
        for (final track in album.tracks) {
          if (kImportedExtraTrackIds.contains(track.id)) continue;
          expect(track.local, isFalse, reason: '${track.id} 不应标记本地');
        }
      }
    });

    test('已下载专辑的曲目 downloaded=true，其余 false', () {
      for (final album in catalog.albums) {
        final expected = kDownloadedAlbumIds.contains(album.id);
        expect(album.downloaded, expected, reason: album.id);
        for (final track in album.tracks) {
          expect(track.downloaded, expected, reason: track.id);
        }
      }
    });

    test('封面路径约定 assets/covers/<albumId>.jpg', () {
      for (final album in catalog.albums) {
        expect(album.cover, 'assets/covers/${album.id}.jpg');
        for (final track in album.tracks) {
          expect(track.cover, album.cover);
        }
      }
    });
  });
}
