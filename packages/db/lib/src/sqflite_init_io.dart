/// 非 web 平台的 sqflite 初始化
///
/// 桌面端（Windows/macOS/Linux）使用 FFI，移动端（Android/iOS）使用默认 sqflite。

import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 初始化 sqflite 工厂
///
/// 桌面端用 FFI（sqfliteFfiInit + databaseFactoryFfi），
/// 移动端用 sqflite 默认工厂（无需额外初始化）。
void initSqfliteForPlatform() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  // 移动端（Android/iOS）使用 sqflite 默认工厂，无需初始化
}

/// 内存数据库路径（测试用）
String getInMemoryDatabasePath() => inMemoryDatabasePath;
