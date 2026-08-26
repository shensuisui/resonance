/// 文件 IO 服务——条件导入入口
///
/// 非 web 环境使用 [file_service_native.dart]（dart:io）
/// web 环境使用 [file_service_web.dart]（空实现）

export 'file_service_native.dart' if (dart.library.html) 'file_service_web.dart';
