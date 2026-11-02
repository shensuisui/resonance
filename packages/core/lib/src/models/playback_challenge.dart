/// 源站要求的人机验证挑战
///
/// 背景：部分源（如歌曲宝）对多数曲目要求先过人机验证才给播放地址 ——
/// 未验证时接口回 {"code":2,"msg":"请完成人机验证后继续"}，而浏览器是带上
/// captchaCode + key 重新请求。旧实现把这种响应当成"没拿到地址"静默吞掉，
/// 用户只看到"无法播放"，无法分辨是解析坏了还是源站拦了。
///
/// 这里把挑战如实回传给上层：UI 可以弹验证图让用户自己过验证（不代破解），
/// 拿到验证码后再带回去重试。
library;

/// 一次人机验证挑战
class PlaybackChallenge {
  /// 验证图（通常形如 data:image/png;base64,...；也可能只是 base64）
  final String image;

  /// 校验用 key：重试时必须原样回传
  final String key;

  /// 回传字段名（验证码本身），如 captchaCode
  final String codeField;

  /// 回传字段名（key），如 key
  final String keyField;

  /// 源站给的提示语（如"请完成人机验证后继续"）
  final String message;

  /// 是否具备可用的验证图
  bool get hasImage => image.isNotEmpty;

  /// 构造
  const PlaybackChallenge({
    required this.image,
    required this.key,
    required this.codeField,
    required this.keyField,
    this.message = '',
  });

  @override
  String toString() => 'PlaybackChallenge(image: ${hasImage ? '有' : '无'}, key: $key)';
}
