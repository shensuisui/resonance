/// 曲目操作的统一入口 —— 把原型 app.js 里分散的 play-track / toggle-like /
/// add-to-queue 行为收敛成可复用方法（现在全部基于 core 的 [Song]）。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/sheets.dart';
import '../providers/providers.dart';

/// 曲目动作
abstract final class TrackActions {
  /// 播放一首歌（自动解析播放地址；源没给地址时提示并返回 false）
  static Future<bool> play(BuildContext context, WidgetRef ref, Song song) async {
    final started = await ref.read(playbackControllerProvider).playSong(song);
    if (!started && context.mounted) {
      showUiV2Toast(context, '「${song.title}」的来源没有提供播放地址');
    }
    return started;
  }

  /// 播放列表里的某一首：队列 = 该列表，从 [index] 开始
  ///
  /// 页面点行必须走这里。用 play(song) 的话队列只剩这一首，
  /// 上一首/下一首会在长度 1 的队列里回绕，表现成"一直播同一首"。
  static Future<bool> playAt(
    BuildContext context,
    WidgetRef ref,
    List<Song> songs,
    int index,
  ) async {
    if (songs.isEmpty) return false;
    final i = index.clamp(0, songs.length - 1);
    final started =
        await ref.read(playbackControllerProvider).playQueue(songs, startIndex: i);
    if (!started && context.mounted) {
      showUiV2Toast(context, '「${songs[i].title}」的来源没有提供播放地址');
    }
    return started;
  }

  /// 播放一组歌曲（从第一首开始）
  static Future<bool> playAll(
      BuildContext context, WidgetRef ref, List<Song> songs) async {
    if (songs.isEmpty) return false;
    final started = await ref.read(playbackControllerProvider).playQueue(songs);
    if (!started && context.mounted) {
      showUiV2Toast(context, '这些曲目的来源没有提供播放地址');
    }
    return started;
  }

  /// 随机播放一组歌曲
  static Future<bool> shuffleAll(
      BuildContext context, WidgetRef ref, List<Song> songs) async {
    if (songs.isEmpty) return false;
    await ref.read(shuffleProvider.notifier).set(true);
    final started = await ref.read(playbackControllerProvider).shuffleQueue(songs);
    if (!started && context.mounted) {
      showUiV2Toast(context, '这些曲目的来源没有提供播放地址');
    }
    return started;
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

  /// 批量加入队列，返回实际加入数量
  static int addAllToQueue(WidgetRef ref, List<Song> songs) {
    final queue = ref.read(queueProvider);
    var added = 0;
    for (final song in songs) {
      if (queue.any((s) => s.globalKey == song.globalKey)) continue;
      ref.read(playbackControllerProvider).addToQueue(song);
      added++;
    }
    return added;
  }
}
