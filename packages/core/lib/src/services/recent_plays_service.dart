import 'package:core/core.dart';

/// 最近播放记录（含歌曲快照）
///
/// 记录播放时保存 title/artist/coverUrl 快照，
/// UI 直接渲染快照即可显示歌曲名，无需回源查询详情。
class RecentPlayRecord {
  /// 全局歌曲键（sourceId:id）
  final String songKey;

  /// 播放时间戳（毫秒）
  final int playedAt;

  /// 歌名快照（可能为 null：历史记录在快照功能前写入）
  final String? title;

  /// 歌手快照
  final String? artist;

  /// 封面 URL 快照
  final String? coverUrl;

  const RecentPlayRecord({
    required this.songKey,
    required this.playedAt,
    this.title,
    this.artist,
    this.coverUrl,
  });
}

/// 最近播放服务
///
/// 封装 RecentPlaysDao 的业务逻辑：
/// - 播放时自动记录（去重 + 移顶）+ 保存歌曲元数据快照
/// - 超出 500 上限自动清理最旧记录
/// - 提供最近播放列表查询
///
/// 使用方式：播放器播放歌曲时调用 [recordPlay]，
/// UI 层通过 [getRecentPlayRecords] 直接读取快照渲染列表。

/// 最近播放记录上限（可配置）
const int kRecentPlaysMaxCount = 500;

class RecentPlaysService {
  final RecentPlaysDao _dao;

  RecentPlaysService(this._dao);

  /// 记录一次播放（同时保存歌曲元数据快照）
  ///
  /// 同一首歌重复播放时更新时间戳（移至列表顶部），
  /// 超过 [kRecentPlaysMaxCount] 时自动清理最旧记录。
  Future<void> recordPlay(Song song) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _dao.insertOrUpdateRecentPlay(
      song.globalKey,
      now,
      title: song.title,
      artist: song.artist,
      coverUrl: song.coverUrl,
    );
    await _dao.cleanOldest(kRecentPlaysMaxCount);
  }

  /// 用补齐后的元数据刷新已有记录的快照（不改播放时间/顺序）
  ///
  /// 封面等详情常在起播后才取到；最近播放列表直接渲染快照，
  /// 若不刷新，列表与启动恢复都会一直用旧快照（无封面）。
  Future<void> updateMetadata(Song song) async {
    final rows = await _dao.getRecentPlayRecords(limit: kRecentPlaysMaxCount);
    for (final row in rows) {
      if (row.songKey != song.globalKey) continue;
      await _dao.insertOrUpdateRecentPlay(
        row.songKey,
        row.playedAt,
        title: song.title.isEmpty ? row.title : song.title,
        artist: song.artist.isEmpty ? row.artist : song.artist,
        coverUrl: (song.coverUrl ?? '').isEmpty ? row.coverUrl : song.coverUrl,
      );
      return;
    }
  }

  /// 获取最近播放的歌曲全局键列表
  ///
  /// 返回按播放时间倒序排列的 songKey 列表，
  /// 调用方通过 SourceManager.getSongDetail 解析为完整 Song。
  Future<List<String>> getRecentSongKeys({int limit = kRecentPlaysMaxCount}) {
    return _dao.getRecentPlayKeys(limit: limit);
  }

  /// 获取最近播放记录（含歌曲快照，按时间倒序）
  Future<List<RecentPlayRecord>> getRecentPlayRecords(
      {int limit = kRecentPlaysMaxCount}) {
    return _dao.getRecentPlayRecords(limit: limit);
  }

  /// 移除一条记录（列表里"我不想在这里再看到它"）
  ///
  /// 只删最近播放这一行，不影响歌曲本身的缓存/收藏/歌单归属。
  Future<void> remove(String songKey) async {
    await _dao.deleteRecentPlay(songKey);
  }

  /// 清空最近播放记录
  ///
  /// 通过 cleanOldest(0) 间接清空。
  Future<void> clear() async {
    await _dao.cleanOldest(0);
  }
}
