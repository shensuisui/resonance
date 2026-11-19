/// AudioCache 的「乙」实现：起播后后台另存一份，`.part` 完整后才算命中
///
/// 为什么不用 DownloadManager：那是「用户主动下载」的语义（写 localPath、
/// 进「已下载」分栏）；播放缓存必须与它分开，否则所有播过的歌都会变成「已下载」。
///
/// 为什么必须 `.part`：绝不把半截文件当缓存播（just_audio 播"还在增长的文件"
/// 会出现时长/seek 不准甚至提前结束）。只有改名成功的完整文件才进索引。
///
/// 为什么文件名用 base64url：把曲目键"清洗"成合法文件名不可逆，重启后无法从
/// 文件名还原曲目键（也就无法重建索引）；base64url 可逆且文件系统安全。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AudioCacheImpl implements AudioCache, AudioCacheFileAccess, AudioCacheStreamWriter {
  /// 下载器（测试可注入）
  final Dio _dio;

  /// 自定义缓存根目录（测试用；为 null 时用应用支持目录）
  final String? customDir;

  /// 根目录（首次使用时创建）
  String? _rootPath;

  /// 已完整缓存的曲目键
  final Set<String> _cached = {};

  /// 下载中的曲目键（同首去重）
  final Set<String> _inflight = {};

  /// 变更广播
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// init 是否已完成（避免 main + binding 重复扫盘）
  bool _initialized = false;

  /// 代际：clear 后自增，阻止在飞下载把文件写回索引
  int _generation = 0;

  /// 在飞下载的取消令牌（clear 时取消）
  final Map<String, CancelToken> _cancelTokens = {};

  /// 流式写入器（同曲去重；clear 时全部中止）
  final Map<String, _AudioCacheStreamSink> _streamSinks = {};

  /// 构造
  AudioCacheImpl({Dio? dio, this.customDir}) : _dio = dio ?? Dio();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Set<String> get cachedKeys => Set.unmodifiable(_cached);

  @override
  bool isCached(String songKey) {
    if (!_cached.contains(songKey)) return false;
    final path = _pathFor(songKey);
    if (path != null && File(path).existsSync()) return true;
    // 外部删除自愈：文件没了就移出索引，避免继续给出坏 file://
    _cached.remove(songKey);
    if (!_changes.isClosed) _changes.add(null);
    return false;
  }

  @override
  String? localUrlFor(String songKey) {
    if (!_cached.contains(songKey)) return null;
    final path = _pathFor(songKey);
    if (path == null || !File(path).existsSync()) {
      _cached.remove(songKey);
      if (!_changes.isClosed) _changes.add(null);
      return null;
    }
    return Uri.file(path).toString();
  }

  @override
  Future<String?> downloadedUrlFor(Song song) async {
    final local = song.localPath;
    if (local == null || local.isEmpty) return null;
    if (!await File(local).exists()) return null;
    return Uri.file(local).toString();
  }

  @override
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final root = await _root();
    _cached.clear();
    if (!await root.exists()) {
      _changes.add(null);
      return;
    }
    await for (final entity in root.list(recursive: true)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      // 下载中的半截文件绝不进索引 —— 这是「乙」的关键保险
      if (name.endsWith('.part')) continue;
      if (await entity.length() == 0) continue;
      final key = _keyOfFileName(name);
      if (key != null) _cached.add(key);
    }
    // 扫盘完成 = 索引才真正可用。必须广播一次：
    // 否则启动时先渲染的列表把 offlineAvailableProvider 的 false 缓存住了，
    // 界面上就是「明明缓存里有、却一直不显示离线可播」（真机实测踩过）。
    _changes.add(null);
  }

  @override
  Future<AudioCacheStreamSink> openStream(String songKey) async {
    await _root();
    final existing = _streamSinks.remove(songKey);
    if (existing != null) await existing.abort();
    final path = _pathFor(songKey);
    if (path == null) throw StateError('缓存目录未初始化');
    final part = File('$path.part');
    await part.parent.create(recursive: true);
    if (await part.exists()) await part.delete();
    final raf = await part.open(mode: FileMode.write);
    final sink = _AudioCacheStreamSink(
      cache: this,
      songKey: songKey,
      targetPath: path,
      partPath: part.path,
      raf: raf,
      generation: _generation,
    );
    _streamSinks[songKey] = sink;
    return sink;
  }

  /// 强制重扫缓存目录（init 幂等；测试/工具需要刷新索引时用）
  Future<void> rescan() async {
    _initialized = false;
    await init();
  }

  @override
  Future<void> cacheAfterPlay(Song song, String url,
      {Map<String, String>? headers}) async {
    final key = song.globalKey;
    if (url.isEmpty || url.startsWith('file:')) return;
    // 已下载的歌不再另存一份（决策：不重复占空间）
    if (await downloadedUrlFor(song) != null) return;
    if (_cached.contains(key) || _inflight.contains(key)) return;

    _inflight.add(key);
    final gen = _generation;
    final token = CancelToken();
    _cancelTokens[key] = token;
    try {
      await _root();
      final path = _pathFor(key);
      if (path == null) return;
      final target = File(path);
      await target.parent.create(recursive: true);
      final part = File('$path.part');
      // 上次没下完的残片直接重下（不做续传，换取实现简单可靠）
      if (await part.exists()) await part.delete();
      await _dio.download(url, part.path,
          options: Options(headers: headers), cancelToken: token);
      // clear() 之后不再把文件写回索引（也不留文件）
      if (gen != _generation || token.isCancelled) {
        if (await part.exists()) await part.delete();
        return;
      }
      final len = await part.length();
      if (len <= 0) {
        await part.delete();
        return;
      }
      await part.rename(target.path); // 只有走到这里才算「完整」
      if (gen != _generation) {
        if (await target.exists()) await target.delete();
        return;
      }
      _cached.add(key);
      _changes.add(null);
      SourceLogBus.instance.emit(song.sourceId, SourceLogLevel.info, '缓存',
          '已缓存 id=${song.id} 大小=${(len / 1024).round()}KB');
    } catch (e) {
      // 失败静默：下次播放这首歌会再试，不打扰用户
      SourceLogBus.instance.emit(song.sourceId, SourceLogLevel.warn, '缓存',
          '缓存失败 id=${song.id}: $e');
    } finally {
      _inflight.remove(key);
      _cancelTokens.remove(key);
    }
  }

  @override
  Future<int> sizeOnDisk() async {
    final root = await _root();
    if (!await root.exists()) return 0;
    var total = 0;
    await for (final e in root.list(recursive: true)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  @override
  Future<void> clear() async {
    _generation++;
    for (final sink in _streamSinks.values.toList()) {
      await sink.abort();
    }
    _streamSinks.clear();
    for (final token in _cancelTokens.values) {
      if (!token.isCancelled) token.cancel();
    }
    _cancelTokens.clear();
    _initialized = false; // 允许下次 init 重新扫盘
    final root = await _root();
    if (await root.exists()) {
      await for (final e in root.list()) {
        try {
          await e.delete(recursive: true);
        } catch (_) {
          // 个别文件被占用时跳过，不阻断整体清空
        }
      }
    }
    _cached.clear();
    _changes.add(null);
  }

  @override
  String? filePathFor(String songKey) {
    if (!_cached.contains(songKey)) return null;
    return _pathFor(songKey);
  }

  @override
  String? targetPathFor(String songKey) => _pathFor(songKey);

  @override
  Future<bool> adoptExistingFile(String songKey) async {
    final path = _pathFor(songKey);
    if (path == null) return false;
    final f = File(path);
    if (!await f.exists() || await f.length() == 0) return false;
    _cached.add(songKey);
    if (!_changes.isClosed) _changes.add(null);
    return true;
  }

  @override
  Future<void> remove(String songKey) async {
    final path = _pathFor(songKey);
    _cached.remove(songKey);
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    if (!_changes.isClosed) _changes.add(null);
  }

  /// 测试/调试用：这首歌的缓存文件路径（未初始化时 null）
  String? debugPathFor(String songKey) => _pathFor(songKey);

  /// 测试用：关闭变更广播
  Future<void> dispose() => _changes.close();

  /// 根目录（懒创建）
  Future<Directory> _root() async {
    final known = _rootPath;
    if (known != null) return Directory(known);
    final base = customDir ??
        p.join((await getApplicationSupportDirectory()).path, 'audio_cache');
    final dir = Directory(base);
    if (!await dir.exists()) await dir.create(recursive: true);
    _rootPath = dir.path;
    return dir;
  }

  /// 缓存文件路径：`<root>/<sourceId>/<base64url(globalKey)>.mp3`
  String? _pathFor(String songKey) {
    final root = _rootPath;
    if (root == null) return null;
    final parts = songKey.split(':');
    final sourceId = parts.isEmpty ? '' : parts.first;
    return p.join(root, sourceId, '${_fileNameOf(songKey)}.mp3');
  }

  String _fileNameOf(String songKey) =>
      base64Url.encode(utf8.encode(songKey)).replaceAll('=', '');

  String? _keyOfFileName(String fileName) {
    if (!fileName.endsWith('.mp3')) return null;
    final bare = fileName.substring(0, fileName.length - 4);
    try {
      final padded = bare + '=' * ((4 - bare.length % 4) % 4);
      return utf8.decode(base64Url.decode(padded));
    } catch (_) {
      return null;
    }
  }
}

class _AudioCacheStreamSink implements AudioCacheStreamSink {
  _AudioCacheStreamSink({
    required this.cache,
    required this.songKey,
    required this.targetPath,
    required this.partPath,
    required this.raf,
    required this.generation,
  });

  final AudioCacheImpl cache;
  final String songKey;
  final String targetPath;
  final String partPath;
  final RandomAccessFile raf;
  final int generation;
  var _bytes = 0;
  var _closed = false;

  @override
  Future<void> add(List<int> bytes) async {
    if (_closed) return;
    await raf.writeFrom(bytes);
    _bytes += bytes.length;
  }

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    try {
      await raf.close();
    } catch (_) {}
  }

  @override
  Future<void> commit() async {
    await _close();
    cache._streamSinks.remove(songKey);
    final part = File(partPath);
    if (generation != cache._generation || _bytes <= 0) {
      if (await part.exists()) await part.delete();
      return;
    }
    final target = File(targetPath);
    if (await target.exists()) await target.delete();
    await part.rename(targetPath);
    cache._cached.add(songKey);
    if (!cache._changes.isClosed) cache._changes.add(null);
  }

  @override
  Future<void> abort() async {
    await _close();
    cache._streamSinks.remove(songKey);
    try {
      final part = File(partPath);
      if (await part.exists()) await part.delete();
    } catch (_) {}
  }
}
