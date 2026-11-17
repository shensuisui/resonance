/// 标签写入抽象（隔离 audiotags 原生 FFI，便于单测注入假实现）
library;

import 'package:audiotags/audiotags.dart';

abstract class TagWriter {
  Future<void> write(String path, Tag tag);
}

class AudioTagsTagWriter implements TagWriter {
  @override
  Future<void> write(String path, Tag tag) => AudioTags.write(path, tag);
}
