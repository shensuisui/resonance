/// 内存 PlaylistDao 的 getSongsUpdatedAt 语义测试
///
/// 与 db 包的 SQLite 实现保持同一语义，供同步层单测使用：
/// 写入/更新后非 0，删除后回到 0。

import 'package:core/core.dart';
import 'package:test/test.dart';

/// 构造一张测试歌单
Playlist _playlist(String id) {
  final now = DateTime.now();
  return Playlist(
    id: id,
    name: '测试',
    songKeys: const ['s:1'],
    createdTime: now,
    modifiedTime: now,
  );
}

void main() {
  test('插入后非 0，更新后前进，删除后回到 0', () async {
    final dao = InMemoryPlaylistDao();
    await dao.insertPlaylist(_playlist('p1'));
    final before = await dao.getSongsUpdatedAt('p1');
    expect(before, greaterThan(0));

    await Future<void>.delayed(const Duration(milliseconds: 2));
    await dao.updatePlaylist(_playlist('p1'));
    expect(await dao.getSongsUpdatedAt('p1'), greaterThan(before));

    await dao.deletePlaylist('p1');
    expect(await dao.getSongsUpdatedAt('p1'), 0);
  });
}
