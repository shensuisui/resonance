/// 规则字段值解析工具（搜索/详情/歌词共用，避免同一逻辑在多处重复）
library;

/// 取标量文本：多值（CSS/XPath 命中多个节点时是 List）取**首个元素**
///
/// 为什么不能直接 toString()：List 的字符串表示自带方括号 ——
/// 标题会变成「[稻香]」这种，看起来像源里带方括号，实际是 List 的表示法
/// （真机现象：列表/播放条标题全都带 []，清洗表达式却"看不出效果"）。
String? parseFieldText(dynamic value) {
  if (value == null) return null;
  if (value is List) {
    if (value.isEmpty) return null;
    return parseFieldText(value.first);
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

/// 把源返回的时长字段解析成秒
///
/// 支持：整数秒、纯数字字符串、"mm:ss"、"hh:mm:ss"。
/// 很多源（如歌曲宝）只给 "03:29" 这种文本，直接 int.tryParse 会得到空时长，
/// 于是列表里长期显示 0:00。解析失败返回 null（不假造数据）。
int? parseDurationSeconds(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final parts = text.split(':');
    if (parts.length >= 2) {
      final nums = parts.map((p) => int.tryParse(p.trim())).toList();
      if (nums.every((n) => n != null)) {
        var seconds = 0;
        for (final n in nums) {
          seconds = seconds * 60 + n!;
        }
        return seconds;
      }
    }
    return int.tryParse(text);
  }
  return null;
}
