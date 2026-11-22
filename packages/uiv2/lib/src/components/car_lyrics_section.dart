/// 设置页「车载歌词」区块
///
/// 配置两项（设备本地）：
///   * 显示范围：关闭 / 仅车载 / 所有蓝牙；
///   * 歌词位置：第一行(title) / 第二行(artist)。
///
/// 两种位置都完整保留「歌手 - 歌名」信息行（与下载命名默认风格一致）。
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/tokens.dart';
import '../design/typography.dart';
import '../providers/providers.dart';
import 'surfaces.dart';

/// 车载歌词设置区块
class CarLyricsSection extends ConsumerWidget {
  /// 构造
  const CarLyricsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final narrow = MediaQuery.sizeOf(context).width < UiV2Breakpoints.wide;
    final scope = ref.watch(carLyricsScopeProvider);
    final slot = ref.watch(carLyricsSlotProvider);

    final scopeHint = switch (scope) {
      CarLyricsScope.off => '关闭 · 不在车机显示歌词',
      CarLyricsScope.car => '仅车载 · 连接车机时显示歌词',
      CarLyricsScope.all => '所有蓝牙 · 任意蓝牙设备都显示歌词',
    };
    final slotHint = slot == CarLyricsSlot.title
        ? '第一行 · 歌词占第一行，歌名与歌手移到第二行'
        : '第二行 · 保留第一行的歌手 - 歌名，歌词显示在第二行';

    return UiV2Section(
      title: '车载歌词',
      child: UiV2Panel(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _segRow(
              context,
              narrow: narrow,
              label: '显示范围',
              hint: scopeHint,
              options: const <(String, String)>[
                ('off', '关闭'),
                ('car', '仅车载'),
                ('all', '所有蓝牙'),
              ],
              value: CarLyricsSettingsKeys.scopeValue(scope),
              onChanged: (v) => ref
                  .read(carLyricsScopeProvider.notifier)
                  .set(CarLyricsSettingsKeys.scopeFrom(v)),
            ),
            _segRow(
              context,
              narrow: narrow,
              label: '歌词位置',
              hint: slotHint,
              options: const <(String, String)>[
                ('title', '第一行'),
                ('artist', '第二行'),
              ],
              value: CarLyricsSettingsKeys.slotValue(slot),
              onChanged: (v) => ref
                  .read(carLyricsSlotProvider.notifier)
                  .set(CarLyricsSettingsKeys.slotFrom(v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Text(
                '车机需支持实时刷新歌曲信息；部分车机只显示第一句或不显示。',
                style: UiV2Text.hint.copyWith(color: t.textDim),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 分段行：窄屏换行到下方，宽屏放行尾（与 _downloadSegRow 同构）
  Widget _segRow(
    BuildContext context, {
    required bool narrow,
    required String label,
    required String hint,
    required List<(String, String)> options,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    final control = UiV2Segmented(
      options: options,
      value: value,
      onChanged: onChanged,
      expand: narrow,
    );
    if (!narrow) {
      return UiV2ListRow(label: label, hint: hint, trailing: control);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: UiV2Text.trackTitle),
          Text(hint, style: UiV2Text.hint),
          const SizedBox(height: 8),
          control,
        ],
      ),
    );
  }
}
