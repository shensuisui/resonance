/// 壳工程实现的文件交互
///
/// 桌面/移动的文件选择与保存走 file_picker；Android 的「用回响打开 .json」
/// 走本文件里的 MethodChannel（resonance/open_file），由 MainActivity 提供。
/// uiv2 只认 FilePickers 契约，不依赖这些平台细节。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:uiv2/uiv2.dart' show FilePickers, OpenedFile;

/// 文件选择器（应用级单例）
class ShellFilePickers implements FilePickers {
  /// 与 MainActivity 约定的通道名
  static const MethodChannel _channel = MethodChannel('resonance/open_file');

  final StreamController<OpenedFile> _opened =
      StreamController<OpenedFile>.broadcast();

  bool _started = false;

  /// 开始监听「外部打开文件」（冷启动的待处理文件 + 运行中新收到的）
  void start() {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openedUri') {
        final uri = (call.arguments as Object?)?.toString();
        if (uri != null && uri.isNotEmpty) await _emit(uri);
      }
      return null;
    });
    unawaited(_readInitial());
  }

  Future<void> _readInitial() async {
    try {
      final uri = await _channel.invokeMethod<String>('getInitialUri');
      if (uri != null && uri.isNotEmpty) await _emit(uri);
    } on MissingPluginException {
      // 桌面/未实现：没有系统打开事件，忽略
    } catch (_) {
      // 任何读取失败都不阻塞启动
    }
  }

  Future<void> _emit(String uri) async {
    try {
      final content = await _channel.invokeMethod<String>('readText', {
        'uri': uri,
      });
      if (content != null && content.isNotEmpty) {
        _opened.add(OpenedFile(path: uri, content: content));
      }
    } catch (_) {
      // 读不到就当没发生（用户可改用「从文件导入」）
    }
  }

  @override
  Stream<OpenedFile> get openedFiles => _opened.stream;

  @override
  Future<String?> pickOpenFile({
    String title = '选择文件',
    List<String> extensions = const <String>[],
  }) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: title,
      type: extensions.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: extensions.isEmpty ? null : extensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    final path = file.path;
    if (path != null && path.isNotEmpty) return path;
    // 某些 Android provider 不给路径，只给字节：落一份缓存文件再读
    final bytes = file.bytes;
    if (bytes == null) return null;
    final temp = File(
      Directory.systemTemp.path + Platform.pathSeparator +
          'resonance_import_' + file.name,
    );
    await temp.writeAsBytes(bytes, flush: true);
    return temp.path;
  }

  @override
  Future<String?> readTextFile(String path) async {
    try {
      return await File(path).readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<int>?> readBinaryFile(String path) async {
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> saveBinaryFile({
    required String title,
    String? suggestedName,
    List<String> extensions = const <String>[],
    required List<int> bytes,
  }) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: title,
      fileName: suggestedName,
      type: extensions.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: extensions.isEmpty ? null : extensions,
      bytes: Uint8List.fromList(bytes),
    );
    if (path == null || path.isEmpty) return null;
    if (!Platform.isAndroid && !Platform.isIOS) {
      await File(path).writeAsBytes(bytes, flush: true);
    }
    return path;
  }

  @override
  Future<String?> saveTextFile({
    required String title,
    String? suggestedName,
    List<String> extensions = const <String>[],
    required String content,
  }) async {
    final bytes = utf8.encode(content);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: title,
      fileName: suggestedName,
      type: extensions.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: extensions.isEmpty ? null : extensions,
      bytes: bytes,
    );
    if (path == null || path.isEmpty) return null;
    // 桌面端 saveFile 只返回路径不写盘；移动端 file_picker 已写入
    if (!Platform.isAndroid && !Platform.isIOS) {
      await File(path).writeAsBytes(bytes, flush: true);
    }
    return path;
  }
}
