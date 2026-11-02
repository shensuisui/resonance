/// 源站人机验证面板
///
/// 用途：部分源（如歌曲宝）对多数曲目要求先过人机验证才给播放地址。
/// 这里把验证图摆出来，让**用户自己**输入验证码（我们不代破解），
/// 提交后带验证码重试换取播放地址。
///
/// 交互：点图片 = 换一张；取消 = 放弃（界面另有一句明确说明）；
/// 提交失败（验证码错）时就地换图重试，不叠面板。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../providers/providers.dart';
import 'sheets.dart';
import 'surfaces.dart';

/// 弹出人机验证面板
///
/// [onSubmit] 返回 [CaptchaSubmitResult]：ok 为 true 时面板自行关闭；
/// 否则就地提示并用返回的新挑战换图。
Future<void> showUiV2CaptchaSheet(
  BuildContext context, {
  required PlaybackChallenge challenge,
  required Future<CaptchaSubmitResult> Function(String code) onSubmit,
  Future<PlaybackChallenge?> Function()? onRefresh,
  VoidCallback? onCancel,
}) {
  return showUiV2Sheet(
    context,
    title: '源站需要人机验证',
    child: UiV2CaptchaSheet(
      challenge: challenge,
      onSubmit: onSubmit,
      onRefresh: onRefresh,
      onCancel: onCancel,
    ),
  );
}

/// 人机验证面板内容（公开以便单测直接 pump）
class UiV2CaptchaSheet extends StatefulWidget {
  /// 源站给的一次挑战
  final PlaybackChallenge challenge;

  /// 提交验证码
  final Future<CaptchaSubmitResult> Function(String code) onSubmit;

  /// 换一张（重新向源站要挑战）
  final Future<PlaybackChallenge?> Function()? onRefresh;

  /// 用户取消
  final VoidCallback? onCancel;

  /// 构造
  const UiV2CaptchaSheet({
    super.key,
    required this.challenge,
    required this.onSubmit,
    this.onRefresh,
    this.onCancel,
  });

  @override
  State<UiV2CaptchaSheet> createState() => _UiV2CaptchaSheetState();
}

class _UiV2CaptchaSheetState extends State<UiV2CaptchaSheet> {
  /// 当前展示的挑战（换一张/失败换图后就地替换，不叠面板）
  late PlaybackChallenge _challenge = widget.challenge;

  /// 验证码输入
  final TextEditingController _controller = TextEditingController();

  /// 是否正在提交/换图（防重复点）
  bool _busy = false;

  /// 错误提示（验证码错、提交失败）
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 验证图字节：支持 data:image/...;base64,xxx 与纯 base64 两种写法
  Uint8List? _imageBytes() {
    final raw = _challenge.image;
    if (raw.isEmpty) return null;
    final b64 = raw.contains(',') ? raw.split(',').last : raw;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.onSubmit(code);
      if (!mounted) return;
      if (result.ok) {
        Navigator.of(context).maybePop();
        return;
      }
      setState(() {
        _busy = false;
        _error = '验证码不正确，请重试';
        if (result.challenge != null) _challenge = result.challenge!;
        _controller.clear();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '提交失败，请重试';
      });
    }
  }

  Future<void> _refresh() async {
    final refresh = widget.onRefresh;
    if (refresh == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final next = await refresh();
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (next != null) _challenge = next;
        _controller.clear();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '换一张失败，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final bytes = _imageBytes();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '源站要求先完成人机验证，才肯给出播放地址。验证码请你自己输入（我们不代破解）。',
          style: UiV2Text.bodyDim.copyWith(color: t.textDim),
        ),
        const SizedBox(height: UiV2Spacing.s4),
        UiV2Pressable(
          key: const ValueKey('captcha_refresh_image'),
          radius: UiV2Radii.brMd,
          onTap: _refresh,
          child: Container(
            height: 68,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: UiV2Radii.brMd,
              border: Border.all(color: t.line),
            ),
            child: bytes == null
                ? Text('验证图加载失败 · 点这里换一张',
                    style: UiV2Text.hint.copyWith(color: t.textDim))
                : Image.memory(
                    bytes,
                    key: const ValueKey('captcha_image'),
                    height: 60,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
          ),
        ),
        const SizedBox(height: UiV2Spacing.s2),
        Text(
          _challenge.message.isEmpty ? '请输入图片中的文字' : _challenge.message,
          style: UiV2Text.hint.copyWith(color: t.textDim),
        ),
        const SizedBox(height: UiV2Spacing.s3),
        TextField(
          key: const ValueKey('captcha_input'),
          controller: _controller,
          autofocus: true,
          enabled: !_busy,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: '输入验证码',
            errorText: _error,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: UiV2Spacing.s4),
        Row(
          children: [
            Expanded(
              child: UiV2Button(
                key: const ValueKey('captcha_cancel'),
                label: '取消',
                variant: UiV2ButtonVariant.soft,
                block: true,
                onTap: () {
                  widget.onCancel?.call();
                  Navigator.of(context).maybePop();
                },
              ),
            ),
            const SizedBox(width: UiV2Spacing.s3),
            Expanded(
              child: UiV2Button(
                key: const ValueKey('captcha_refresh'),
                label: '换一张',
                variant: UiV2ButtonVariant.soft,
                block: true,
                onTap: _busy ? null : _refresh,
              ),
            ),
            const SizedBox(width: UiV2Spacing.s3),
            Expanded(
              child: UiV2Button(
                key: const ValueKey('captcha_submit'),
                label: _busy ? '提交中…' : '确定',
                variant: UiV2ButtonVariant.primary,
                block: true,
                onTap: _busy ? null : _submit,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
