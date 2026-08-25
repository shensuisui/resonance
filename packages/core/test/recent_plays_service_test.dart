/// RecentPlaysService 单元测试
///
/// 使用 InMemoryDatabaseProvider，验证：
/// - recordPlay 自动记录 + 去重移顶
/// - 500 上限自动清理
/// - getRecentSongKeys 按时间倒序
/// - clear 清空记录
/// - 播放顺序恢复（重复播放移至顶部）

import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  late InMemoryDatabaseProvider db;
  late RecentPlaysService service;

  setUp(() {
    db = InMemoryDatabaseProvider();
    service = RecentPlaysService(db.recentPlaysDao);
  });

  group('RecentPlaysService', () {
    test('recordPlay 记录单首歌曲', () async {
      final song = Song(id: '1', sourceId: 's', title: '歌', artist: '手');
      await service.recordPlay(song);

      final keys = await service.getRecentSongKeys();
      expect(keys.length, 1);
      expect(keys.first, song.globalKey);
    });

    test('recordPlay 多首歌曲按时间倒序', () async {
      final song1 = Song(id: '1', sourceId: 's', title: '歌1', artist: '手');
      final song2 = Song(id: '2', sourceId: 's', title: '歌2', artist: '手');
      final song3 = Song(id: '3', sourceId: 's', title: '歌3', artist: '手');

      // 按顺序播放，间隔 1ms 确保时间戳不同
      await service.recordPlay(song1);
      await Future.delayed(const Duration(milliseconds: 1));
      await service.recordPlay(song2);
      await Future.delayed(const Duration(milliseconds: 1));
      await service.recordPlay(song3);

      final keys = await service.getRecentSongKeys();
      expect(keys.length, 3);
      // 最近播放的在前
      expect(keys[0], song3.globalKey);
      expect(keys[1], song2.globalKey);
      expect(keys[2], song1.globalKey);
    });

    test('recordPlay 重复播放移至顶部（去重）', () async {
      final song1 = Song(id: '1', sourceId: 's', title: '歌1', artist: '手');
      final song2 = Song(id: '2', sourceId: 's', title: '歌2', artist: '手');

      await service.recordPlay(song1);
      await Future.delayed(const Duration(milliseconds: 1));
      await service.recordPlay(song2);
      await Future.delayed(const Duration(milliseconds: 1));
      // song1 重复播放
      await service.recordPlay(song1);

      final keys = await service.getRecentSongKeys();
      expect(keys.length, 2); // 去重后仍为 2
      expect(keys.first, song1.globalKey); // 移至顶部
    });

    test('getRecentSongKeys limit 参数生效', () async {
      for (int i = 0; i < 10; i++) {
        await service.recordPlay(
            Song(id: '$i', sourceId: 's', title: '歌$i', artist: '手'));
        await Future.delayed(const Duration(milliseconds: 1));
      }

      final keys = await service.getRecentSongKeys(limit: 5);
      expect(keys.length, 5);
      // 最近的 5 首（9, 8, 7, 6, 5）
      expect(keys.first, 's:9');
      expect(keys.last, 's:5');
    });

    test('clear 清空所有记录', () async {
      await service.recordPlay(
          Song(id: '1', sourceId: 's', title: '歌', artist: '手'));
      await service.clear();

      final keys = await service.getRecentSongKeys();
      expect(keys, isEmpty);
    });

    test('不同源相同 id 不互相覆盖', () async {
      final songA =
          Song(id: '1', sourceId: 'sourceA', title: 'A', artist: '手');
      final songB =
          Song(id: '1', sourceId: 'sourceB', title: 'B', artist: '手');

      await service.recordPlay(songA);
      await Future.delayed(const Duration(milliseconds: 1));
      await service.recordPlay(songB);

      final keys = await service.getRecentSongKeys();
      expect(keys.length, 2);
      expect(keys, containsAll([songA.globalKey, songB.globalKey]));
    });
  });
}
