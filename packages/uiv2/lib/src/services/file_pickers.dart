/// 外部文件交互契约（由壳工程注入实现）
///
/// 为什么抽出来：uiv2 是纯 UI 包，刻意不依赖 file_picker / 平台通道。
/// 导入导出、分享、系统「用回响打开 .json」都需要选择/读写文件，
/// 这些平台能力由 resonance_app 注入，uiv2 只调用本接口。
library;

/// 外部传入的一个文件（系统「用回响打开」时产生）
class OpenedFile {
  /// 文件路径（桌面为真实路径；Android 为 content:// 或缓存副本路径）
  final String path;

  /// 文件文本内容（壳工程已读好，uiv2 只负责解析）
  final String content;

  /// 构造
  const OpenedFile({required this.path, required this.content});
}

/// 文件选择/读写能力
abstract class FilePickers {
  /// 选择要导入的文件（返回路径；用户取消返回 null）
  Future<String?> pickOpenFile({
    String title = '选择文件',
    List<String> extensions = const <String>[],
  });

  /// 读取文本文件（Android 的 content:// 由壳工程解析后返回内容）
  Future<String?> readTextFile(String path);

  /// 保存文本文件（选择位置 + 写入一步完成）
  ///
  /// 为什么不分两步：Android 的 SAF 只给出 content:// 句柄，拿不到可写的
  /// 文件路径，必须由能访问 ContentResolver 的壳工程在同一处完成写入。
  /// 返回保存后的展示路径；用户取消返回 null。
  Future<String?> saveTextFile({
    required String title,
    String? suggestedName,
    List<String> extensions = const <String>[],
    required String content,
  });

  /// 系统「用回响打开文件」事件：
  /// 冷启动时的待处理文件会在订阅后先补发一次，运行中新收到的持续推送。
  Stream<OpenedFile> get openedFiles;
}
