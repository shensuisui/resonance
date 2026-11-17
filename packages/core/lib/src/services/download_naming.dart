/// 下载文件命名与扩展名推断工具（纯函数，可复用给 UI 预览）
library;

/// 非法字符清洗：替换为 _，去首尾空格，最长 120 字符
String sanitizeFileNamePart(String input) {
  final cleaned = input
      .replaceAll(RegExp(r'[\\/:*?"<>|' + '\x00-\x1f' + ']'), '_')
      .trim();
  if (cleaned.isEmpty) return '';
  return cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned;
}

/// 生成可读文件名：`<歌手> - <歌曲>`（或反之）。extension 不含点。
String buildDownloadFileName({
  required String title,
  String? artist,
  String order = 'artist_title',
  String extension = 'mp3',
}) {
  final t = sanitizeFileNamePart(title);
  final a = artist == null ? '' : sanitizeFileNamePart(artist);
  final name = (order == 'title_artist')
      ? (t.isNotEmpty && a.isNotEmpty
          ? '$t - $a'
          : (t.isNotEmpty ? t : a))
      : (a.isNotEmpty && t.isNotEmpty
          ? '$a - $t'
          : (a.isNotEmpty ? a : t));
  final base = name.isEmpty ? 'untitled' : name;
  return '$base.$extension';
}

/// 同一目录下冲突时追加 ` (2)`、` (3)`…（existing 为已存在文件名集合）
String uniqueFileName(String baseWithExt, Set<String> existing) {
  if (!existing.contains(baseWithExt)) return baseWithExt;
  final dot = baseWithExt.lastIndexOf('.');
  final name = dot <= 0 ? baseWithExt : baseWithExt.substring(0, dot);
  final ext = dot <= 0 ? '' : baseWithExt.substring(dot);
  var n = 2;
  while (true) {
    final candidate = '$name ($n)$ext';
    if (!existing.contains(candidate)) return candidate;
    n++;
  }
}

/// 按字节头推断音频扩展名（不含点）；无法识别返回 null
String? detectAudioExtension(List<int> bytes) {
  if (bytes.isEmpty) return null;
  final head = String.fromCharCodes(bytes.take(12).toList());
  if (head.startsWith('fLaC')) return 'flac';
  if (head.startsWith('OggS')) return 'ogg';
  if (head.startsWith('ID3')) return 'mp3';
  if (bytes.length >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) {
    return 'mp3'; // MPEG audio sync word 0xFF Ex
  }
  if (bytes.length >= 8 && String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') {
    return 'm4a';
  }
  return null;
}
