/// 混合返回模型：真实历史 + 跨分支回来路 + 高亮一致
///
/// 这些用例锁住用户体感里最容易“跳错页”的路径：
///   * 首页 → 最近播放 → 返回首页（不是“我的”）；
///   * 音乐库 → 歌单列表 → 歌单 → 逐级返回；
///   * 歌单 A → 歌单 B → 返回 A；
///   * 切底部 tab 清空历史；
///   * 移动端 liked/local 的返回与高亮跟随来路。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/router.dart';

NavEntry e(String name, [String param = '']) => NavEntry(name, param);

void main() {
  group('NavState.visit / backTarget', () {
    test('同分支逐级：音乐库 → 歌单列表 → 歌单，返回逐级回到上一页', () {
      var s = NavState(current: e('library'));
      s = s.visit(e('playlists'));
      s = s.visit(e('playlist', 'p1'));

      expect(s.current, e('playlist', 'p1'));
      expect(s.trail, <NavEntry>[e('library'), e('playlists')]);

      final back1 = s.backTarget()!;
      expect(back1.current, e('playlists'));
      final back2 = back1.backTarget()!;
      expect(back2.current, e('library'));
      expect(back2.backTarget(), isNull);
    });

    test('跨分支：首页 → 最近播放，返回首页而不是“我的”', () {
      var s = NavState(current: e('home'));
      s = s.visit(e('recent'));

      expect(s.current, e('recent'));
      expect(s.trail, <NavEntry>[e('home')]);
      expect(s.backTarget()!.current, e('home'));
      // 最近播放属于 profile 分支，但来路是首页 → 高亮首页
      expect(activeBranch(s, wide: false), 'home');
    });

    test('同栏目互跳：歌单 A → 歌单 B，返回 A（不是音乐库）', () {
      var s = NavState(current: e('library'));
      s = s.visit(e('playlist', 'A'));
      s = s.visit(e('playlist', 'B'));

      expect(s.backTarget()!.current, e('playlist', 'A'));
      expect(s.backTarget()!.current.param, 'A');
      expect(activeBranch(s, wide: false), 'library');
    });

    test('切底部 tab 清空历史；新 tab 再进二级页重新记录', () {
      var s = NavState(current: e('home'));
      s = s.visit(e('recent'));
      expect(s.trail, isNotEmpty);

      s = s.visit(e('search'));
      expect(s.trail, isEmpty);

      s = s.visit(e('settings'));
      expect(s.trail, <NavEntry>[e('search')]);
    });

    test('移动端 liked/local：高亮跟随来路，没有来路时回落到栏目', () {
      // 从“我的”进入我喜欢的音乐
      var s = NavState(current: e('profile')).visit(e('liked'));
      expect(activeBranch(s, wide: false), 'profile');
      expect(s.backTarget()!.current, e('profile'));

      // 从“音乐库”进入本地音乐
      s = NavState(current: e('library')).visit(e('local'));
      expect(activeBranch(s, wide: false), 'library');

      // 直接深链进入（无历史）：liked 回落 profile，local 回落 library
      expect(activeBranch(NavState(current: e('liked')), wide: false), 'profile');
      expect(activeBranch(NavState(current: e('local')), wide: false), 'library');
    });

    test('桌面：一级页高亮自己（忽略历史）', () {
      final s = NavState(current: e('liked'), trail: <NavEntry>[e('profile')]);
      expect(activeBranch(s, wide: true), 'liked');
      // 桌面二级页仍由来路决定
      final detail =
          NavState(current: e('settings'), trail: <NavEntry>[e('profile')]);
      expect(activeBranch(detail, wide: true), 'profile');
    });

    test('历史带上限，异常循环不会无限增长', () {
      var s = NavState(current: e('library'));
      for (var i = 0; i < 30; i++) {
        s = s.visit(e('playlist', 'p' + i.toString()));
      }
      expect(s.trail.length, 20);
    });
  });
}
