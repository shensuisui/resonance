/// 内存 DAO 的同步读取接口测试
///
/// 与 db 的 SQLite 实现保持同样语义：全量 + 非 0 更新时间；
/// 删除后不再出现。

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('InMemorySongDao.getAllSongRecords 带更新时间，删除后消失', () async {
    final dao = InMemorySongDao();
    await dao.insertSong(
      const Song(id: '1', sourceId: 's', title: 'A', artist: 'X'),
    );
    var records = await dao.getAllSongRecords();
    expect(records.single.updatedAt, greaterThan(0));

    await dao.deleteSong('1', 's');
    records = await dao.getAllSongRecords();
    expect(records, isEmpty);
  });

  test('InMemorySettingsDao.getAllEntries 带更新时间与值', () async {
    final dao = InMemorySettingsDao();
    await dao.set('theme_mode', 'dark');
    final entries = await dao.getAllEntries();
    expect(entries.single.key, 'theme_mode');
    expect(entries.single.value, 'dark');
    expect(entries.single.updatedAt, greaterThan(0));
  });
}
