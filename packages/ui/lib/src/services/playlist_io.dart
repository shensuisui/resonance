/// 歌单导入/导出服务
///
/// 基于 file_picker 选择保存/打开路径，
/// 使用 core 的 PlaylistCodec 做 M3U/PLS/JSON 编解码。
///
/// 导出：歌单详情页 → 选格式 → 选保存位置 → 写入文件
/// 导入：歌单列表页 → 选文件 → 解析 → 创建歌单（本地源歌曲写入 DB）

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:core/core.dart';

/// 导出格式
enum PlaylistFormat {
  m3u('M3U 播放列表', 'm3u'),
  pls('PLS 播放列表', 'pls'),
  json('回响歌单 (JSON)', 'json');

  const PlaylistFormat(this.label, this.extension);

  final String label;
  final String extension;
}

class PlaylistIo {
  PlaylistIo._();

  /// 将 Song 列表转为 PlaylistEntry
  static List<PlaylistEntry> songsToEntries(List<Song> songs) {
    return songs.map((s) => PlaylistEntry(
          title: s.title,
          artist: s.artist,
          url: s.playUrl,
          localPath: s.localPath,
        )).toList();
  }

  /// 导出歌单
  ///
  /// 返回是否成功。用户取消选择返回 false。
  static Future<bool> exportPlaylist(
    String name,
    List<Song> songs,
    PlaylistFormat format,
  ) async {
    final entries = songsToEntries(songs);

    // 生成内容
    final String content;
    switch (format) {
      case PlaylistFormat.m3u:
        content = PlaylistCodec.encodeM3U(entries);
      case PlaylistFormat.pls:
        content = PlaylistCodec.encodePLS(entries);
      case PlaylistFormat.json:
        content = PlaylistCodec.encodeJson(name, entries);
    }

    // 选择保存路径
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: '导出歌单',
      fileName: '$name.${format.extension}',
      type: FileType.custom,
      allowedExtensions: [format.extension],
    );
    if (savePath == null || savePath.isEmpty) return false;

    // 写入文件
    await File(savePath).writeAsString(content);
    return true;
  }

  /// 导入歌单
  ///
  /// 返回解析结果，用户取消返回 null。
  static Future<PlaylistImportResult?> importPlaylist() async {
    // 选择文件
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '导入歌单',
      type: FileType.custom,
      allowedExtensions: ['m3u', 'pls', 'json'],
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    final path = file.path;
    if (path == null || path.isEmpty) return null;

    final content = await File(path).readAsString();
    final ext = path.split('.').last.toLowerCase();

    switch (ext) {
      case 'm3u':
        return PlaylistImportResult(entries: PlaylistCodec.decodeM3U(content));
      case 'pls':
        return PlaylistImportResult(entries: PlaylistCodec.decodePLS(content));
      case 'json':
        return PlaylistCodec.decodeJson(content);
      default:
        return null;
    }
  }

  /// 将导入的条目转为 Song（存入本地源）
  ///
  /// - localPath 非空 → sourceId='local_scan'（本地扫描源）
  /// - 否则 url 非空 → sourceId='local_custom'（自定义源）
  /// - 两者都空 → 跳过
  static List<Song> entriesToSongs(List<PlaylistEntry> entries) {
    final songs = <Song>[];
    for (final e in entries) {
      if (e.localPath != null && e.localPath!.isNotEmpty) {
        songs.add(Song(
          id: 'imp_${e.localPath!.hashCode.toUnsigned(32).toString()}',
          sourceId: 'local_scan',
          title: e.title,
          artist: e.artist,
          localPath: e.localPath,
        ));
      } else if (e.url != null && e.url!.isNotEmpty) {
        songs.add(Song(
          id: 'imp_${e.url!.hashCode.toUnsigned(32).toString()}',
          sourceId: 'local_custom',
          title: e.title,
          artist: e.artist,
          playUrl: e.url,
        ));
      }
    }
    return songs;
  }
}
