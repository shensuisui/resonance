/// 曲目操作的统一入口 —— 把原型 app.js 里分散的 play-track / toggle-like /
/// add-to-queue 行为收敛成可复用方法（现在全部基于 core 的 [Song]）。
///
/// **队列纪律**（用户规则）：所有播放都发生在某个队列里，列表页点行 = 把当前队列
/// 换成该列表；"搜索候选/首页卡片/推荐单曲/已下载"这类**非列表**入口则记入最近播放
/// 并切到最近播放队列。队列切换只在**起播成功后**发生。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/sheets.dart';
import '../providers/providers.dart';

/// 曲目动作
abstract final class TrackActions {
  /// 队列构造：歌单（自建 / 远程收藏）
  static PlayQueue playlistQueue(Playlist playlist, List<Song> songs) => PlayQueue(
        kind: PlayQueueKind.playlist,
        id: playlist.id,
        title: playlist.name,
        songs: songs,
      );

  /// 队列构造：我喜欢的音乐
  static PlayQueue likedQueue(List<Song> songs) => PlayQueue(
        kind: PlayQueueKind.liked,
        title: '我喜欢的音乐',
        songs: songs,
      );

  /// 队列构造：本地音乐
  static PlayQueue localQueue(List<Song> songs) => PlayQueue(
        kind: PlayQueueKind.local,
        title: '本地音乐',
        songs: songs,
      );

  /// 队列构造：最近播放
  static PlayQueue recentQueue(List<Song> songs) => PlayQueue(
        kind: PlayQueueKind.recent,
        title: '最近播放',
        songs: songs,
      );

  /// **列表页点行的唯一入口**：把当前队列换成 [queue] 并从第 [index] 首开始播
  ///
  /// 队列切换只在起播成功后发生（见 PlaybackController.playInQueue）：
  /// 点一首播不出来的歌，不会把"在播那首属于哪个队列"搞错。
  static Future<bool> playInQueue(
    BuildContext context,
    WidgetRef ref,
    PlayQueue queue,
    int index,
  ) async {
    if (queue.isEmpty) return false;
    final i = index.clamp(0, queue.length - 1);
    final started =
        await ref.read(playbackControllerProvider).playInQueue(queue, startIndex: i);
    if (!started && context.mounted) {
      showUiV2Toast(context, '「' + queue.songs[i].title + '」的来源没有提供播放地址');
    }
    return started;
  }

  /// 播放整个队列（从第一首开始）
  static Future<bool> playQueueAll(
      BuildContext context, WidgetRef ref, PlayQueue queue) =>
      playInQueue(context, ref, queue, 0);

  /// 随机播放一个队列：打乱交给播放器的随机模式，**队列身份不变**
  static Future<bool> shuffleQueueAll(
      BuildContext context, WidgetRef ref, PlayQueue queue) async {
    if (queue.isEmpty) return false;
    final started = await ref.read(playbackControllerProvider).shuffleInQueue(queue);
    if (!started && context.mounted) {
      showUiV2Toast(context, '这个队列的来源没有提供播放地址');
    }
    return started;
  }

  /// **单曲入口**（搜索候选 / 首页卡片 / 推荐单曲 / 已下载）：
  /// 先记入最近播放（它成为队首），再把当前队列切成最近播放。
  static Future<bool> playAsRecent(
      BuildContext context, WidgetRef ref, Song song) async {
    // 记一笔：最近播放以"最近一次播放"为序，所以它就是队首
    await ref.read(recentProvider.notifier).record(song);
    final songs = ref.read(recentSongsProvider);
    final index = songs.indexWhere((s) => s.globalKey == song.globalKey);
    return playInQueue(context, ref, recentQueue(songs), index < 0 ? 0 : index);
  }

  /// 切换喜欢并提示
  static Future<void> toggleLike(
      BuildContext context, WidgetRef ref, Song song) async {
    final wasLiked =
        ref.read(likedProvider).any((r) => r.songKey == song.globalKey);
    await ref.read(likedProvider.notifier).toggle(song);
    if (context.mounted) {
      showUiV2Toast(
        context,
        wasLiked ? '已从「我喜欢的音乐」移除' : '已加入「我喜欢的音乐」',
      );
    }
  }
}
