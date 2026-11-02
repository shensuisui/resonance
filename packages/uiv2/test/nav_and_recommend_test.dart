/// 导航标题与首页推荐区块的决策测试
///
/// 两个真实缺陷的回归：
///   ① 手机模式下歌单详情顶部显示「未找到」——因为 kRouteTitles 漏登记了
///      'playlist'，而兜底文案就是"未找到"这类吓人的字；
///   ② 首页「推荐歌曲」在没有真实推荐时，把演示曲库的 8 首搬上来顶位，
///      等于假装有推荐（用户明确要求：整块隐藏）。
library;

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/pages/home_page.dart';
import 'package:uiv2/src/router.dart';

/// 造一个歌单（推荐源返回值）
Playlist _playlist(String name, {String sourceId = 's', String id = 'p'}) =>
    Playlist(
      id: id,
      name: name,
      sourceId: sourceId,
      createdTime: DateTime(2026, 11, 2),
      modifiedTime: DateTime(2026, 11, 2),
    );

/// 造一首歌
Song _song(String id) => Song(id: id, sourceId: 's', title: '曲' + id, artist: '');

void main() {
  group('页面标题', () {
    test('歌单详情有标题（不再显示「未找到」）', () {
      expect(titleOf(const NavEntry('playlist', 'some-id')), '歌单');
    });

    test('未登记的新路由兜底为空串，而不是「未找到」', () {
      expect(titleOf(const NavEntry('brand-new-route')), isEmpty);
    });

    test('显式 override 优先（页面可以用真实歌单名）', () {
      expect(
        titleOf(const NavEntry('playlist', 'p1'), override: '默认1'),
        '默认1',
      );
    });
  });

  group('首页推荐区块（没有真实推荐就整块隐藏）', () {
    test('还没有推荐歌单：返回空（隐藏）', () {
      expect(
        pickRecommendedSongs(playlists: null, songsOfPicked: null),
        isEmpty,
      );
      expect(
        pickRecommendedSongs(playlists: const [], songsOfPicked: const []),
        isEmpty,
      );
    });

    test('有推荐歌单但曲目还没读到 / 为空：隐藏', () {
      final list = [_playlist('每日推荐')];
      expect(pickRecommendedSongs(playlists: list, songsOfPicked: null), isEmpty);
      expect(
        pickRecommendedSongs(playlists: list, songsOfPicked: const []),
        isEmpty,
      );
    });

    test('有真实曲目：取前 limit 首展示', () {
      final list = [_playlist('每日推荐', id: 'p9')];
      final songs = <Song>[for (var i = 0; i < 12; i++) _song(i.toString())];
      final out = pickRecommendedSongs(playlists: list, songsOfPicked: songs);
      expect(out.length, 8, reason: '首页只展示前 8 首');
      expect(out.first.id, '0');
    });

    test('优先挑名字带「今日/推荐/每日」的歌单', () {
      final list = [_playlist('随便一个'), _playlist('每日推荐', id: 'p2')];
      expect(pickRecommendedPlaylist(list)?.id, 'p2');
    });
  });
}
