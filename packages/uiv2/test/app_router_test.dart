/// 路由门面（navProvider）与位置编码的回归测试
///
/// 迁移到 go_router 后，外部仍只调 navProvider.go/back；这里钉住三件事：
///   ① 路由名 → 位置 → 路由名 往返一致（参数里有 :: 与斜杠也不能坏）；
///   ② go 一级页切分支、go 二级页压栈、back 逐级退回；
///   ③ 二级页归属的一级页（branchOf）与 kParentRoute 口径一致。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:uiv2/src/app_router.dart';
import 'package:uiv2/src/router.dart';

void main() {
  test('位置编码往返：普通参数 / 带 :: 的远端歌单 / 带斜杠的参数', () {
    for (final param in <String>[
      '',
      'up-1793536576026725',
      'qq::1234567890',
      'a/b/c',
      '带 空格 和 中文',
    ]) {
      final location = locationOf('playlist', param);
      final entry = navEntryFromUri(Uri.parse(location));
      expect(entry.name, 'playlist', reason: '路径要能反解成路由名：$location');
      expect(entry.param, param, reason: '参数必须无损往返：$location');
    }
  });

  test('一级页位置不带查询参数', () {
    expect(locationOf('home'), '/home');
    expect(locationOf('library'), '/library');
    expect(navEntryFromUri(Uri.parse('/home')).param, '');
  });

  test('二级页归属的一级页与 kParentRoute 口径一致', () {
    for (final name in kRouteDefs.map((d) => d.name)) {
      final def = kRouteDefByName[name]!;
      if (def.parent == null) {
        expect(isRootRoute(name), isTrue, reason: '$name 应是一级页');
        expect(branchOf(name), name);
      } else {
        expect(isRootRoute(name), isFalse, reason: '$name 应是二级页');
        expect(branchOf(name), def.parent, reason: '$name 的分支应是 ${def.parent}');
        expect(kParentRoute[name], def.parent,
            reason: '$name 在 kParentRoute 里的上一级应与分支一致（返回键靠它兜底）');
      }
      // 路径必须唯一，否则 go_router 匹配的是第一个
      expect(kRouteNameByPath.containsKey(def.path), isTrue);
    }
  });

  test('未登记的路径回落到首页（不崩）', () {
    expect(navEntryFromUri(Uri.parse('/nope/whatever')).name, 'home');
  });
}
