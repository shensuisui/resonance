/// 最近播放服务
///
/// 封装 RecentPlaysDao 的业务逻辑：
/// - 播放时自动记录（去重 + 移顶）
/// - 超出 500 上限自动清理最旧记录
/// - 提供最近播放列表查询
///
/// 使用方式：播放器播放歌曲时调用 [recordPlay]，
/// UI 层通过 [getRecentSongKeys] 获取列表后用 SourceManager 解析为 Song。

import 'package:core/core.dart';

/// 最近播放记录上限（可配置）
const int kRecentPlaysMaxCount = 500;

class RecentPlaysService {
  final RecentPlaysDao _dao;

  RecentPlaysService(this._dao);

  /// 记录一次播放
  ///
  /// 同一首歌重复播放时更新时间戳（移至列表顶部），
  /// 超过 [kRecentPlaysMaxCount] 时自动清理最旧记录。
  Future<void> recordPlay(Song song) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _dao.insertOrUpdateRecentPlay(song.globalKey, now);
    await _dao.cleanOldest(kRecentPlaysMaxCount);
  }

  /// 获取最近播放的歌曲全局键列表
  ///
  /// 返回按播放时间倒序排列的 songKey 列表，
  /// 调用方通过 SourceManager.getSongDetail 解析为完整 Song。
  Future<List<String>> getRecentSongKeys({int limit = kRecentPlaysMaxCount}) {
    return _dao.getRecentPlayKeys(limit: limit);
  }

  /// 清空最近播放记录
  ///
  /// 通过 cleanOldest(0) 间接清空。
  Future<void> clear() async {
    await _dao.cleanOldest(0);
  }
}
