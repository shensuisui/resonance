/// 播放缓存「索引就绪」通知的回归测试
///
/// 现场：最近播放里两首歌明明在缓存目录里，界面上却一直不显示「离线可播」。
/// 根因：AudioCacheImpl.init() 扫盘后没有广播变更 → 启动时先渲染的列表把
/// offlineAvailableProvider 的 false 缓存住了，直到别的歌写缓存才被动刷新。
///
/// 这里钉住契约：init() 完成后 changes 必须发一次事件（索引可用即视为变更）。
library;

import 'dart:io';

import 'package:db/db.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('init() 扫盘完成后广播一次变更（让界面刷新离线可播标记）', () async {
    final dir = Directory.systemTemp.createTempSync('resonance_cache_');
    try {
      // 造一个真实缓存文件：<root>/<sourceId>/<base64url(key)>.mp3
      final f = File(dir.path + '/demo/some.mp3');
      await f.parent.create(recursive: true);
      await f.writeAsBytes(List<int>.filled(16, 0));

      final cache = AudioCacheImpl(customDir: dir.path);
      var events = 0;
      final sub = cache.changes.listen((_) => events++);
      // 先订阅再 init：与真实接线顺序一致（先接流，再扫盘）
      await cache.init();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();

      expect(events, greaterThanOrEqualTo(1),
          reason: 'init 之后必须广播，否则界面上的离线标记会永久停在旧值');
    } finally {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });
}
