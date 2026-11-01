/// 订阅页 —— 通过 SubscriptionHost 宿主对接真实订阅库
///
/// uiv2 不直接依赖 packages/ui（避免两套 UI 互相纠缠），订阅的持久化与源展开
/// 逻辑由壳工程注入 [SubscriptionHost]（对应 ui 包的 SubscriptionLibrary）。
/// 未注入时给出明确说明，不伪造数据。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/sheets.dart';
import '../components/surfaces.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../providers/providers.dart';
import '../router.dart';
import '../widgets/page_shell.dart';

/// 订阅页
class SubsPage extends ConsumerWidget {
  /// 构造页面
  const SubsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final host = ref.watch(subscriptionHostProvider);
    final sources = ref.watch(sourceListProvider).value ?? const [];

    return PageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(
            title: '订阅',
            sub: '订阅会把一个远程地址展开成 1~N 个音乐源；当前已注册 ${sources.length} 个源。',
          ),
          if (host == null)
            UiV2Panel(
              padding: const EdgeInsets.all(UiV2Spacing.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '订阅管理能力未接入。',
                    style: UiV2Text.rowLabel.copyWith(color: t.text),
                  ),
                  const SizedBox(height: UiV2Spacing.s2),
                  Text(
                    'uiv2 通过壳工程注入的 SubscriptionHost 管理订阅；当前宿主为空，'
                    '说明这个入口还没被壳工程装配。可以在「音乐源」页管理已注册的源，'
                    '或等宿主接入后再回来添加订阅。',
                    style: UiV2Text.bodyDim.copyWith(color: t.textDim),
                  ),
                ],
              ),
            )
          else ...[
            UiV2Section(
              title: '添加订阅',
              child: UiV2Panel(
                padding: const EdgeInsets.all(UiV2Spacing.s4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '订阅内容只保存在本地，不会上传；地址会被展开成对应数量的音乐源。',
                      style: UiV2Text.hint.copyWith(color: t.textDim),
                    ),
                    const SizedBox(height: UiV2Spacing.s3),
                    _AddSubscriptionBox(host: host),
                    const SizedBox(height: UiV2Spacing.s3),
                    UiV2Button(
                      label: '${host.count()} 条订阅 · 点击检查全部更新',
                      icon: UiV2Icons.clock,
                      variant: UiV2ButtonVariant.soft,
                      block: true,
                      onTap: () async {
                        final (ok, fail) = await host.checkAll();
                        if (context.mounted) {
                          showUiV2Toast(
                            context,
                            '检查完成：成功 $ok · 失败 $fail',
                            info: fail > 0,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            UiV2Section(
              title: '已展开的源',
              child: UiV2Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < sources.length; i++)
                      UiV2ListRow(
                        label: sources[i].sourceInfo.name,
                        hint: 'ID ${sources[i].sourceInfo.id}',
                        divider: i < sources.length - 1,
                        trailing: const UiV2Chevron(),
                        onTap: () =>
                            ref.read(navProvider.notifier).go('sources'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 添加订阅：填一个远程规则 JSON 地址，交给宿主展开成音乐源
///
/// 输入框自己管 controller（页面是 ConsumerWidget，不持有可变状态）。
class _AddSubscriptionBox extends ConsumerStatefulWidget {
  /// 订阅宿主（页面已判空后才构造本组件）
  final SubscriptionHost host;

  /// 构造
  const _AddSubscriptionBox({required this.host});

  @override
  ConsumerState<_AddSubscriptionBox> createState() =>
      _AddSubscriptionBoxState();
}

class _AddSubscriptionBoxState extends ConsumerState<_AddSubscriptionBox> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = _controller.text.trim();
    if (url.isEmpty) {
      showUiV2Toast(context, '请先填写订阅地址');
      return;
    }
    setState(() => _busy = true);
    final ok = await widget.host.add(url, 'rule', null);
    if (!mounted) return;
    setState(() => _busy = false);
    showUiV2Toast(
      context,
      ok ? '订阅已展开成音乐源' : '订阅失败：地址无效或内容不是规则 JSON',
      info: !ok,
    );
    if (ok) {
      _controller.clear();
      // 让「已展开的源」立刻刷新
      ref.invalidate(sourceListProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          style: UiV2Text.body.copyWith(color: t.text),
          decoration: InputDecoration(
            hintText: 'https://example.com/rules.json',
            hintStyle: UiV2Text.body.copyWith(color: t.textMute),
            filled: true,
            fillColor: t.surface2,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: UiV2Spacing.s4,
              vertical: UiV2Spacing.s3,
            ),
            border: OutlineInputBorder(
              borderRadius: UiV2Radii.brMd,
              borderSide: BorderSide(color: t.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: UiV2Radii.brMd,
              borderSide: BorderSide(color: t.line),
            ),
          ),
        ),
        const SizedBox(height: UiV2Spacing.s2),
        UiV2Button(
          label: _busy ? '正在展开…' : '添加订阅',
          icon: UiV2Icons.plus,
          variant: UiV2ButtonVariant.primary,
          block: true,
          onTap: _busy ? null : _submit,
        ),
      ],
    );
  }
}
