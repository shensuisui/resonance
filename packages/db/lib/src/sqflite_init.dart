/// SQLite 初始化——条件导入入口
///
/// 非 web 环境使用 [sqflite_init_io.dart]（sqflite_common_ffi）
/// web 环境使用 [sqflite_init_web.dart]（sqflite_common_ffi_web，实验性）

export 'sqflite_init_io.dart' if (dart.library.html) 'sqflite_init_web.dart';
