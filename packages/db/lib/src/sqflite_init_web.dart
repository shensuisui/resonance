/// Web 平台的 sqflite 初始化（实验性）
///
/// 使用 [sqflite_common_ffi_web] 提供 WebAssembly SQLite。
/// 需要在 web/ 目录下提供 sqlite3.wasm 和 drl.flite3-drvc.wasm 文件。
///
/// 当前为 no-op 占位——web SQLite 需要额外配置 WASM 文件，
/// 未配置时数据库操作会抛异常，但编译不会失败。
/// 未来完善后替换为真实的 web factory 初始化。

/// 初始化 web sqflite 工厂
///
/// 当前为 no-op。要启用 web SQLite：
/// 1. 在 pubspec 中添加 sqflite_common_ffi_web
/// 2. 在 web/ 目录提供 sqlite3.wasm 文件
/// 3. 替换此方法为 databaseFactory = createDatabaseFactoryWeb()
void initSqfliteForPlatform() {
  // Web SQLite 需要额外配置，暂为 no-op
}

/// 内存数据库路径
String getInMemoryDatabasePath() => ':memory:';
