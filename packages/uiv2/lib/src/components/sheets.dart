/// 弹层与提示 —— 对应原型 .sheet / .sheet-scrim / .toasts，
/// 以及 openQueue / openSleepSheet / openDevices / openTrackMenu / openConfirm。
///
/// 断点行为与原型一致：≤1023 底部抽屉；≥1024 居中对话框（560px / 80vh）。
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalog.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../providers/providers.dart';
import '../router.dart';
import '../widgets/track_actions.dart';
import 'rows.dart';
import 'surfaces.dart';

// ==================== 提示（toast） ====================

/// 一条提示
class UiV2ToastItem {
  /// 自增 id
  final int id;

  /// 文案
  final String message;

  /// 是否为信息类（图标 info，否则 check）
  final bool info;

  /// 操作按钮文案（如「撤销」）
  final String? actionLabel;

  /// 操作回调
  final VoidCallback? onAction;

  /// 构造提示
  const UiV2ToastItem({
    required this.id,
    required this.message,
    this.info = false,
    this.actionLabel,
    this.onAction,
  });
}

/// 提示队列（原型 #toasts：2200ms 自动消失，撤销类 2000ms）
class UiV2ToastNotifier extends Notifier<List<UiV2ToastItem>> {
  int _seq = 0;

  @override
  List<UiV2ToastItem> build() => const [];

  /// 追加一条提示
  void show(
    String message, {
    bool info = false,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(milliseconds: 2200),
  }) {
    final item = UiV2ToastItem(
      id: ++_seq,
      message: message,
      info: info,
      actionLabel: actionLabel,
      onAction: onAction,
    );
    state = [...state, item];
    Timer(duration, () {
      state = state.where((t) => t.id != item.id).toList();
    });
  }

  /// 移除一条提示
  void dismiss(int id) {
    state = state.where((t) => t.id != id).toList();
  }
}

/// 提示 Provider
final toastProvider =
    NotifierProvider<UiV2ToastNotifier, List<UiV2ToastItem>>(UiV2ToastNotifier.new);

/// 弹出一条提示（在任意 BuildContext 内调用）
void showUiV2Toast(BuildContext context, String message, {bool info = false}) {
  final container = ProviderScope.containerOf(context, listen: false);
  container.read(toastProvider.notifier).show(message, info: info);
}

/// 提示浮层（.toasts）—— 栈式排布于播放条上方 140px 处
class UiV2ToastHost extends ConsumerWidget {
  /// 底部偏移（默认播放条 64 + 76）
  final double bottomOffset;

  /// 构造提示浮层
  const UiV2ToastHost({super.key, this.bottomOffset = 140});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toasts = ref.watch(toastProvider);
    if (toasts.isEmpty) return const SizedBox.shrink();
    final width = MediaQuery.sizeOf(context).width;
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottomOffset,
      child: IgnorePointer(
        ignoring: false,
        child: Center(
          child: SizedBox(
            width: width * 0.92 > 380 ? 380 : width * 0.92,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final toast in toasts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: UiV2Spacing.s2),
                    child: UiV2FadeIn(child: _ToastView(toast: toast)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastView extends ConsumerWidget {
  final UiV2ToastItem toast;

  const _ToastView({required this.toast});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: UiV2Spacing.s4,
        vertical: UiV2Spacing.s3,
      ),
      decoration: BoxDecoration(
        color: t.surface3,
        borderRadius: UiV2Radii.brMd,
        boxShadow: t.shadow2,
      ),
      child: Row(
        children: [
          UiV2Icon(
            toast.info ? UiV2Icons.info : UiV2Icons.check,
            size: 20,
            color: t.ok,
          ),
          const SizedBox(width: UiV2Spacing.s3),
          Expanded(
            child: Text(
              toast.message,
              style: UiV2Text.rowLabel.copyWith(color: t.text),
            ),
          ),
          if (toast.actionLabel != null) ...[
            const SizedBox(width: UiV2Spacing.s3),
            UiV2Pressable(
              onTap: () {
                toast.onAction?.call();
                ref.read(toastProvider.notifier).dismiss(toast.id);
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: 32),
                padding: const EdgeInsets.symmetric(horizontal: UiV2Spacing.s3),
                decoration: BoxDecoration(
                  color: t.accent,
                  borderRadius: UiV2Radii.brPill,
                ),
                alignment: Alignment.center,
                child: Text(
                  toast.actionLabel!,
                  style: UiV2ButtonTextStyle.of(t),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// toast 操作按钮文字样式（.toast__act：13/700）
abstract final class UiV2ButtonTextStyle {
  /// 取样式
  static TextStyle of(UiV2Tokens t) =>
      UiV2Text.buttonSmall.copyWith(color: t.accentInk, fontWeight: FontWeight.w700);
}

// ==================== 弹层（sheet） ====================

/// 打开弹层（原型 openSheet 的 Flutter 版）
///
/// [title] 标题；[child] 内容；[onClosed] 关闭后回调（原型 opts.onClose）。
Future<void> showUiV2Sheet(
  BuildContext context, {
  required String title,
  required Widget child,
  VoidCallback? onClosed,
}) async {
  final wide = MediaQuery.sizeOf(context).width >= UiV2Breakpoints.desktop;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: Colors.transparent,
    transitionDuration: UiV2Motion.d3,
    pageBuilder: (context, animation, secondaryAnimation) {
      return UiV2SheetFrame(title: title, wide: wide, child: child);
    },
    transitionBuilder: (context, animation, secondaryAnimation, pageChild) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: UiV2Motion.enter,
        reverseCurve: UiV2Motion.exit,
      );
      if (wide) {
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
            child: pageChild,
          ),
        );
      }
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: pageChild,
      );
    },
  );
  onClosed?.call();
}

/// 弹层外框（.sheet-scrim + .sheet）
class UiV2SheetFrame extends ConsumerWidget {
  /// 标题
  final String title;

  /// 是否居中对齐（桌面）
  final bool wide;

  /// 内容
  final Widget child;

  /// 构造外框
  const UiV2SheetFrame({
    super.key,
    required this.title,
    required this.wide,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final inset = MediaQuery.paddingOf(context);
    final maxHeight = MediaQuery.sizeOf(context).height * (wide ? 0.8 : 0.82);

    final sheet = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        width: wide ? 560 : double.infinity,
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.line),
          borderRadius: wide
              ? UiV2Radii.brXl
              : const BorderRadius.only(
                  topLeft: UiV2Radii.xl,
                  topRight: UiV2Radii.xl,
                ),
          boxShadow: t.shadow3,
        ),
        clipBehavior: Clip.antiAlias,
        padding: EdgeInsets.only(bottom: wide ? 0 : inset.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!wide)
              Padding(
                padding: const EdgeInsets.only(top: UiV2Spacing.s3),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.lineStrong,
                    borderRadius: UiV2Radii.brPill,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: UiV2Spacing.s4,
                vertical: UiV2Spacing.s3,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: UiV2Text.sheetTitle.copyWith(color: t.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  UiV2IconButton(
                    icon: UiV2Icons.close,
                    semanticLabel: '关闭',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: t.line),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(UiV2Spacing.s4),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(color: t.scrim),
            ),
          ),
          if (wide)
            Center(child: sheet)
          else
            Align(alignment: Alignment.bottomCenter, child: sheet),
        ],
      ),
    );
  }
}

/// 弹层内的动作行（.action-row）
class UiV2ActionRow extends StatelessWidget {
  /// 图标名
  final String icon;

  /// 文案
  final String label;

  /// 说明
  final String? hint;

  /// 危险态
  final bool danger;

  /// 点击回调（null 表示禁用）
  final VoidCallback? onTap;

  /// 构造动作行
  const UiV2ActionRow({
    super.key,
    required this.icon,
    required this.label,
    this.hint,
    this.danger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final color = danger ? t.danger : t.text;
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: UiV2Pressable(
        onTap: onTap,
        radius: UiV2Radii.brMd,
        hoverColor: disabled ? null : t.surface2,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: UiV2Spacing.s3),
          child: Row(
            children: [
              UiV2Icon(icon, size: 22, color: danger ? t.danger : t.textDim),
              const SizedBox(width: UiV2Spacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: UiV2Text.actionRow.copyWith(color: color)),
                    if (hint != null && hint!.isNotEmpty)
                      Text(hint!, style: UiV2Text.hint.copyWith(color: t.textDim)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== 播放队列弹层 ====================

/// 打开播放队列（原型 openQueue）
Future<void> showQueueSheet(BuildContext context) {
  return showUiV2Sheet(
    context,
    title: '播放队列',
    child: const UiV2QueueSheetBody(),
  );
}

/// 队列弹层内容
class UiV2QueueSheetBody extends ConsumerStatefulWidget {
  /// 构造队列内容
  const UiV2QueueSheetBody({super.key});

  @override
  ConsumerState<UiV2QueueSheetBody> createState() => _UiV2QueueSheetBodyState();
}

class _UiV2QueueSheetBodyState extends ConsumerState<UiV2QueueSheetBody> {
  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    // 队列是 core 的 Song 列表（queueProvider），不再从配表还原曲目
    final queue = ref.watch(queueProvider);
    final currentKey = ref.watch(currentTrackIdProvider);
    final mode = ref.watch(playModeProvider);
    final shuffle = ref.watch(shuffleProvider);
    final catalogTracks = ref.watch(catalogTracksProvider);
    final playing = ref.watch(isPlayingProvider);
    final pendingKey = ref.watch(pendingProvider);

    if (queue.isEmpty) {
      return const UiV2Empty(
        title: '播放队列是空的',
        text: '播放任意歌曲后，队列会显示在这里。',
        icon: UiV2Icons.queue,
      );
    }

    final modeText = shuffle
        ? '随机播放'
        : switch (mode) {
            PlayMode.listLoop => '列表循环',
            PlayMode.singleLoop => '单曲循环',
            PlayMode.sequential => '顺序播放',
            PlayMode.shuffle => '随机播放',
          };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${queue.length} 首 · $modeText',
                style: UiV2Text.hint.copyWith(color: t.textDim),
              ),
            ),
            UiV2GhostMini(
              label: '清空队列',
              onTap: () {
                // clearQueue 默认保留当前播放的那首（keepCurrent），与原型口径一致
                ref.read(playbackControllerProvider).clearQueue();
                _toast(ref, currentKey == null ? '队列已清空' : '已清空队列（保留正在播放的这首）');
              },
            ),
          ],
        ),
        const SizedBox(height: UiV2Spacing.s3),
        Text(
          '拖动左侧把手调整顺序，向左滑动可移除（2 秒内可撤销）。队列不持久化，重启后为空。',
          style: UiV2Text.hint.copyWith(color: t.textDim),
        ),
        const SizedBox(height: UiV2Spacing.s3),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          // onReorderItem 已经在内部换算过 newIndex，无需再手动 -1
          onReorderItem: (from, to) =>
              ref.read(playbackControllerProvider).reorderQueue(from, to),
          itemCount: queue.length,
          itemBuilder: (context, index) {
            final song = queue[index];
            final key = song.globalKey;
            // 队列可能同时存在不同来源的同名曲目，key 用「全局键 + 下标」保证唯一
            final isCurrent = key == currentKey;
            // 配表只当展示元数据：有就用它的封面（随包资产），没有就退回 Song 自带封面
            final cover = _metaOf(catalogTracks, song)?.cover ?? song.coverUrl;
            return ReorderableDragStartListener(
              key: ValueKey('${key}_$index'),
              index: index,
              child: _QueueRow(
                index: index,
                title: song.title,
                artist: song.artist,
                cover: cover,
                isCurrent: isCurrent,
                isPlaying: isCurrent && playing,
                isPending: isCurrent && pendingKey == key,
                duration: song.duration ?? 0,
                onTap: () => ref.read(playbackControllerProvider).jumpTo(index),
                onRemove: isCurrent ? null : () => _removeAt(context, ref, index, song),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// 取配表展示元数据（[catalogTracksProvider] 的键是曲目 id）
CatalogTrack? _metaOf(Map<String, CatalogTrack> map, Song song) => map[song.id];

/// 从队列移除一首歌并给出可撤销提示
///
/// 撤销要同时恢复 UI 队列与播放器队列：只改一边会让下一次「下一首」跳到别处，
/// 所以这里用 PlaybackController.addToQueue 之后的队列做插入。
void _removeAt(BuildContext context, WidgetRef ref, int index, Song song) {
  final controller = ref.read(playbackControllerProvider);
  final removed = controller.removeFromQueue(index);
  if (removed == null) {
    showUiV2Toast(context, '正在播放的这首歌不能从队列移除');
    return;
  }
  final container = ProviderScope.containerOf(context, listen: false);
  container.read(toastProvider.notifier).show(
        '已从队列移除「${removed.title}」',
        info: true,
        // 撤销：2 秒内可恢复（原型 offerQueueUndo + toastUndo）
        actionLabel: '撤销',
        duration: const Duration(milliseconds: 2000),
        onAction: () {
          // 先补齐播放器队列（到队尾），再把这首歌按原下标插回 UI 队列
          container.read(playbackControllerProvider).addToQueue(removed);
          container.read(queueProvider.notifier).insertAt(index, removed);
        },
      );
}

/// 在弹层内弹提示
///
/// 弹层里的动作常常在关闭弹层之后才弹提示，那时 [BuildContext] 已经失效，
/// 所以这里统一用还是挂载状态的 [WidgetRef] 取容器。
void _toast(WidgetRef ref, String message, {bool info = false}) {
  ProviderScope.containerOf(ref.context, listen: false)
      .read(toastProvider.notifier)
      .show(message, info: info);
}

/// 队列行（.track--queue：把手 + 封面 + 文本 + 时长 + 操作）
class _QueueRow extends ConsumerWidget {
  final int index;
  final String title;
  final String artist;
  final String? cover;
  final bool isCurrent;
  final bool isPlaying;
  final bool isPending;
  final int duration;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _QueueRow({
    required this.index,
    required this.title,
    required this.artist,
    required this.cover,
    required this.isCurrent,
    required this.isPlaying,
    required this.isPending,
    required this.duration,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final overlay = (isPlaying || isPending)
        ? Container(
            color: const Color(0x8C060709),
            alignment: Alignment.center,
            child: isPending
                ? UiV2Spinner(
                    trackColor: const Color(0x57FFFFFF),
                    color: const Color(0xFFFFFFFF),
                  )
                : UiV2Eq(color: const Color(0xFFFFFFFF)),
          )
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: UiV2Spacing.s2,
          vertical: UiV2Spacing.s2,
        ),
        decoration: BoxDecoration(
          color: isCurrent ? t.accentSoft : const Color(0x00000000),
          borderRadius: UiV2Radii.brMd,
        ),
        child: Row(
          children: [
            // 拖拽把手（.track__grip：三条横线）
            SizedBox(
              width: 18,
              height: 36,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      width: 10,
                      height: 2,
                      margin: const EdgeInsets.symmetric(vertical: 1.5),
                      decoration: BoxDecoration(
                        color: t.textMute,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: UiV2Spacing.s2),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Row(
                  children: [
                    UiV2Cover(source: cover, size: 42, overlay: overlay),
                    const SizedBox(width: UiV2Spacing.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: UiV2Text.trackTitle.copyWith(
                              color: isCurrent ? t.accent : t.text,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            artist,
                            style: UiV2Text.trackArtist.copyWith(color: t.textDim),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Text(
              // formatSeconds 与曲目行/播放条同一套格式化（catalog.formatDuration 已不再引入）
              formatSeconds(duration),
              style: UiV2Text.duration.copyWith(color: t.textMute),
            ),
            const SizedBox(width: UiV2Spacing.s2),
            if (isCurrent)
              const Padding(
                padding: EdgeInsets.only(right: UiV2Spacing.s2),
                child: UiV2Badge(label: '播放中', tone: UiV2BadgeTone.accent),
              ),
            UiV2IconButton(
              icon: UiV2Icons.close,
              semanticLabel: '从队列移除：$title',
              size: 36,
              disabled: onRemove == null,
              onTap: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 睡眠定时器弹层 ====================

/// 打开睡眠定时器（原型 openSleepSheet）
Future<void> showSleepSheet(BuildContext context) {
  return showUiV2Sheet(
    context,
    title: '睡眠定时器',
    child: const UiV2SleepSheetBody(),
  );
}

/// 睡眠定时器内容
class UiV2SleepSheetBody extends ConsumerWidget {
  /// 构造内容
  const UiV2SleepSheetBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final remain = ref.watch(sleepTimerProvider);
    final notifier = ref.read(sleepTimerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (remain != null) ...[
          // formatDuration 来自已移除的配表模块，这里用组件层的 formatSeconds（同为 m:ss）
          UiV2SleepNow(remain: formatSeconds(remain.inSeconds)),
          UiV2Button(
            label: '取消定时器',
            icon: UiV2Icons.close,
            variant: UiV2ButtonVariant.outline,
            block: true,
            onTap: () {
              notifier.cancel();
              showUiV2Toast(context, '已取消睡眠定时器');
              Navigator.of(context).maybePop();
            },
          ),
          const SizedBox(height: UiV2Spacing.s4),
          Text('重新设定', style: UiV2Text.rowLabel.copyWith(color: t.text)),
          const SizedBox(height: UiV2Spacing.s2),
        ] else ...[
          Text(
            '设定一段时间后自动暂停播放。睡眠定时器不会在重启后保留。',
            style: UiV2Text.hint.copyWith(color: t.textDim),
          ),
          const SizedBox(height: UiV2Spacing.s4),
          Text('暂停时间', style: UiV2Text.rowLabel.copyWith(color: t.text)),
          const SizedBox(height: UiV2Spacing.s2),
        ],
        for (var i = 0; i < kSleepMinutes.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: UiV2Spacing.s2),
            child: Row(
              children: [
                Expanded(
                  child: UiV2Button(
                    label: '${kSleepMinutes[i]} 分钟',
                    variant: UiV2ButtonVariant.soft,
                    block: true,
                    onTap: () {
                      notifier.start(Duration(minutes: kSleepMinutes[i]));
                      showUiV2Toast(context, '已设定 ${kSleepMinutes[i]} 分钟后暂停播放');
                      Navigator.of(context).maybePop();
                    },
                  ),
                ),
                const SizedBox(width: UiV2Spacing.s2),
                if (i + 1 < kSleepMinutes.length)
                  Expanded(
                    child: UiV2Button(
                      label: '${kSleepMinutes[i + 1]} 分钟',
                      variant: UiV2ButtonVariant.soft,
                      block: true,
                      onTap: () {
                        notifier.start(Duration(minutes: kSleepMinutes[i + 1]));
                        showUiV2Toast(
                          context,
                          '已设定 ${kSleepMinutes[i + 1]} 分钟后暂停播放',
                        );
                        Navigator.of(context).maybePop();
                      },
                    ),
                  )
                else
                  const Expanded(child: SizedBox.shrink()),
              ],
            ),
          ),
      ],
    );
  }
}

// ==================== 播放设备弹层 ====================

/// 打开播放设备选择（原型 openDevices）
Future<void> showDeviceSheet(BuildContext context) {
  return showUiV2Sheet(
    context,
    title: '选择播放设备',
    child: const UiV2DeviceSheetBody(),
  );
}

/// 播放设备内容
class UiV2DeviceSheetBody extends ConsumerWidget {
  /// 构造内容
  const UiV2DeviceSheetBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final current = ref.watch(deviceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final device in kDeviceOptions)
          UiV2ActionRow(
            icon: UiV2Icons.device,
            label: device.name,
            hint: device.name == current ? '当前设备' : device.hint,
            onTap: () async {
              await ref.read(deviceProvider.notifier).set(device.name);
              if (context.mounted) {
                showUiV2Toast(context, '已切换到「${device.name}」');
                Navigator.of(context).maybePop();
              }
            },
          ),
        const SizedBox(height: UiV2Spacing.s2),
        Text(
          '演示实现：设备列表为固定配表，切换只记录当前设备名。',
          style: UiV2Text.hint.copyWith(color: t.textDim),
        ),
      ],
    );
  }
}

// ==================== 曲目菜单弹层 ====================

/// 打开一首歌的更多操作（原型 openTrackMenu）
///
/// 首选传 [song]（真实 [Song]）；[trackId] 是兼容旧调用点的入口，
/// 传入后会同步用 [songByIdProvider] 解析成 [Song]，解析不出来时给出空态而不是假数据。
Future<void> showTrackMenu(
  BuildContext context, {
  Song? song,
  String? trackId,
  VoidCallback? onRemove,
}) {
  return showUiV2Sheet(
    context,
    title: '更多操作',
    child: UiV2TrackMenuBody(song: song, trackId: trackId, onRemove: onRemove),
  );
}

/// 曲目菜单内容（.action-row 列表）
class UiV2TrackMenuBody extends ConsumerWidget {
  /// 目标曲目（优先于 [trackId]）
  final Song? song;

  /// 目标曲目 id（null 表示当前播放曲目）
  final String? trackId;

  /// 「从歌单移除」回调（只在歌单详情里传；其它入口为 null 就不显示这一项）
  final VoidCallback? onRemove;

  /// 构造内容
  const UiV2TrackMenuBody({super.key, this.song, this.trackId, this.onRemove});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 三种来源的优先级：显式 Song > 当前播放曲目 > 显式 id（需要异步解析）
    final target = song ?? (trackId == null ? ref.watch(currentSongProvider) : null);
    if (target != null) {
      return _TrackMenuActions(song: target, onRemove: onRemove);
    }

    final id = trackId ?? ref.watch(currentTrackIdProvider);
    if (id == null) {
      return const UiV2Empty(
        title: '先挑一首歌',
        text: '从首页或音乐库点开任意一首，再回到这里。',
        icon: UiV2Icons.note,
      );
    }
    // 只有 id 时回源补一次详情（远程源首次进入才需要）
    return ref.watch(songByIdProvider(id)).when(
          data: (resolved) => resolved != null
              ? _TrackMenuActions(song: resolved, onRemove: onRemove)
              : const UiV2Empty(
                  title: '这首曲子暂时取不到详情',
                  text: '来源没有返回它的信息，稍后再试试。',
                  icon: UiV2Icons.info,
                ),
          loading: () => Padding(
            padding: const EdgeInsets.all(UiV2Spacing.s6),
            child: Center(
              // 弹层底色随主题，转圈用 tokens 取色才能在任何主题下看得见
              child: UiV2Spinner(
                size: 20,
                trackColor: UiV2Theme.of(context).surface3,
                color: UiV2Theme.of(context).accent,
              ),
            ),
          ),
          error: (error, stack) => const UiV2Empty(
            title: '这首曲子暂时取不到详情',
            text: '来源没有返回它的信息，稍后再试试。',
            icon: UiV2Icons.info,
          ),
        );
  }
}

/// 曲目菜单的动作列表（拿到 [Song] 之后渲染）
class _TrackMenuActions extends ConsumerWidget {
  /// 目标曲目
  final Song song;

  /// 「从歌单移除」回调（歌单详情才有）
  final VoidCallback? onRemove;

  /// 构造动作列表
  const _TrackMenuActions({required this.song, this.onRemove});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    final key = song.globalKey;
    final title = song.title;
    final meta = _metaOf(ref.watch(catalogTracksProvider), song);
    final liked = ref.watch(likedProvider).any((r) => r.songKey == key);
    final inQueue = ref.watch(queueProvider).any((s) => s.globalKey == key);
    // 演示曲库（随包资产）走配表封面，其它源退回 Song 自带封面
    final cover = meta?.cover ?? song.coverUrl;
    // Song.album 是专辑名：真实能力只有名字（没有 id），作为路由参数足够；为空则禁用该项
    final albumParam = song.album ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 曲目摘要（封面 + 歌名 + 歌手），替代原来只有一行的说明文案
        Padding(
          padding: const EdgeInsets.only(bottom: UiV2Spacing.s3),
          child: Row(
            children: [
              UiV2Cover(source: cover, size: 44),
              const SizedBox(width: UiV2Spacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: UiV2Text.trackTitle.copyWith(color: t.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      song.artist.isEmpty ? '未知歌手' : song.artist,
                      style: UiV2Text.hint.copyWith(color: t.textDim),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        UiV2ActionRow(
          icon: UiV2Icons.play,
          label: '立即播放',
          onTap: () async {
            Navigator.of(context).maybePop();
            // 源没给播放地址时 playSong 返回 false，由 TrackActions 统一提示
            await TrackActions.play(context, ref, song);
          },
        ),
        UiV2ActionRow(
          icon: UiV2Icons.next,
          label: '下一首播放',
          onTap: () {
            ref.read(playbackControllerProvider).playNextUp(song);
            Navigator.of(context).maybePop();
            _toast(ref, '已设为下一首播放');
          },
        ),
        UiV2ActionRow(
          icon: UiV2Icons.queue,
          label: '加入播放队列',
          onTap: () {
            if (inQueue) {
              Navigator.of(context).maybePop();
              _toast(ref, '队列里已经有「$title」');
              return;
            }
            ref.read(playbackControllerProvider).addToQueue(song);
            Navigator.of(context).maybePop();
            _toast(ref, '已加入播放队列');
          },
        ),
        UiV2ActionRow(
          icon: liked ? UiV2Icons.heartFill : UiV2Icons.heart,
          label: liked ? '取消喜欢' : '喜欢',
          onTap: () async {
            await ref.read(likedProvider.notifier).toggle(song);
            if (!context.mounted) return;
            Navigator.of(context).maybePop();
            _toast(ref, liked ? '已从「我喜欢的音乐」移除' : '已加入「我喜欢的音乐」');
          },
        ),
        UiV2ActionRow(
          icon: UiV2Icons.plus,
          label: '添加到歌单',
          hint: '把这首歌收进自建歌单',
          onTap: () => showAddToPlaylistSheet(context, song),
        ),
        if (onRemove != null)
          UiV2ActionRow(
            icon: UiV2Icons.trash,
            label: '从歌单移除',
            hint: '这首歌会从当前歌单里删掉，歌曲本身不受影响',
            danger: true,
            onTap: () {
              Navigator.of(context).maybePop();
              onRemove!();
            },
          ),
        UiV2ActionRow(
          icon: UiV2Icons.disc,
          label: '查看专辑',
          hint: albumParam.isEmpty ? '这首曲子没有专辑信息' : albumParam,
          // 专辑名缺失时没有可跳转的目标，禁用比跳到空页面好
          onTap: albumParam.isEmpty
              ? null
              : () {
                  Navigator.of(context).maybePop();
                  ref.read(navProvider.notifier).go('album', albumParam);
                },
        ),
        _DownloadActionRow(song: song, title: title),
        UiV2ActionRow(
          icon: UiV2Icons.share,
          label: '复制分享链接',
          hint: '演示实现：只给提示，不写剪贴板',
          onTap: () {
            Navigator.of(context).maybePop();
            _toast(ref, '链接已复制');
          },
        ),
      ],
    );
  }
}

/// 「下载 / 删除缓存」动作行 —— 用 [DownloadActions] 查真实缓存状态
class _DownloadActionRow extends ConsumerStatefulWidget {
  /// 目标曲目
  final Song song;

  /// 曲目名（提示文案用）
  final String title;

  /// 构造动作行
  const _DownloadActionRow({required this.song, required this.title});

  @override
  ConsumerState<_DownloadActionRow> createState() => _DownloadActionRowState();
}

class _DownloadActionRowState extends ConsumerState<_DownloadActionRow> {
  /// 是否已缓存（null = 还在查询）
  bool? _cached;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// 查询缓存状态
  Future<void> _refresh() async {
    try {
      final cached = await ref
          .read(downloadActionsProvider)
          .isCached(widget.song.globalKey);
      if (mounted) setState(() => _cached = cached);
    } catch (_) {
      // 下载管理器未接入时按「未缓存」处理，避免整行卡在加载态
      if (mounted) setState(() => _cached = false);
    }
  }

  /// 下载或删除缓存
  Future<void> _toggle() async {
    final actions = ref.read(downloadActionsProvider);
    if (_cached == true) {
      await actions.deleteCache(widget.song.globalKey);
      if (!mounted) return;
      setState(() => _cached = false);
      _toast(ref, '已删除「${widget.title}」的缓存');
      return;
    }
    await actions.download(widget.song);
    if (!mounted) return;
    await _refresh();
    _toast(ref, '已开始下载「${widget.title}」');
  }

  @override
  Widget build(BuildContext context) {
    final cached = _cached;
    if (cached == null) {
      return const UiV2ActionRow(
        icon: UiV2Icons.download,
        label: '下载',
        hint: '正在查询缓存状态…',
        onTap: null,
      );
    }
    return UiV2ActionRow(
      icon: UiV2Icons.download,
      label: cached ? '删除缓存' : '下载',
      hint: cached ? '删除后需要重新下载才能离线使用' : '下载到本地缓存',
      onTap: _toggle,
    );
  }
}

/// 打开「添加到歌单」（原型 openAddToPlaylist）
Future<void> showAddToPlaylistSheet(BuildContext context, Song song) {
  return showUiV2Sheet(
    context,
    title: '添加到歌单',
    child: UiV2AddToPlaylistBody(song: song),
  );
}

/// 「添加到歌单」内容：自建歌单列表，点一下即加入 / 移出
class UiV2AddToPlaylistBody extends ConsumerStatefulWidget {
  /// 目标曲目
  final Song song;

  /// 构造内容
  const UiV2AddToPlaylistBody({super.key, required this.song});

  @override
  ConsumerState<UiV2AddToPlaylistBody> createState() =>
      _UiV2AddToPlaylistBodyState();
}

class _UiV2AddToPlaylistBodyState extends ConsumerState<UiV2AddToPlaylistBody> {
  /// 正在写入的歌单 id（避免连点重复写库，也用来给行加禁用态）
  String? _busy;

  /// 切换「这首歌是否在某个歌单里」
  ///
  /// 用 song.globalKey 与 Playlist.songKeys 比较：歌单里存的是全局键，
  /// 不是曲目 id（同一首曲子在不同源下是不同的歌）。
  Future<void> _toggle(Playlist playlist) async {
    if (_busy != null) return;
    final key = widget.song.globalKey;
    final inside = playlist.songKeys.contains(key);
    setState(() => _busy = playlist.id);
    try {
      final actions = ref.read(playlistActionsProvider);
      final ok = inside
          ? await actions.removeSong(playlist.id, key)
          : await actions.addSong(playlist.id, widget.song);
      if (!mounted) return;
      if (!ok) {
        // 已在内 / 不在内属于并发点击的竞态，给一句提示即可
        _toast(ref, inside ? '「${playlist.name}」里已经没有这首歌' : '这首歌已经在「${playlist.name}」里了');
        return;
      }
      _toast(ref, inside ? '已从「${playlist.name}」移除' : '已加入「${playlist.name}」');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    final playlists = ref.watch(playlistsProvider);
    final key = widget.song.globalKey;

    return playlists.when(
      data: (list) {
        if (list.isEmpty) {
          return UiV2Empty(
            title: '还没有自建歌单',
            text: '先创建一个歌单，再把这歌收进去。',
            icon: UiV2Icons.queue,
            actions: UiV2Button(
              label: '去歌单页新建',
              variant: UiV2ButtonVariant.primary,
              onTap: () {
                Navigator.of(context).maybePop();
                ref.read(navProvider.notifier).go('playlists');
              },
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '点一下即可加入或移出，改动会立即保存。',
              style: UiV2Text.hint.copyWith(color: t.textDim),
            ),
            const SizedBox(height: UiV2Spacing.s3),
            for (final playlist in list)
              UiV2ActionRow(
                icon: playlist.songKeys.contains(key)
                    ? UiV2Icons.check
                    : UiV2Icons.plus,
                label: playlist.name,
                hint: '${playlist.songKeys.length} 首'
                    '${playlist.songKeys.contains(key) ? ' · 已在内' : ''}',
                // 写入中把其它行禁用，保证一次只写一个歌单
                onTap: _busy == null ? () => _toggle(playlist) : null,
              ),
          ],
        );
      },
      loading: () => Padding(
        padding: const EdgeInsets.all(UiV2Spacing.s6),
        child: Center(
          child: UiV2Spinner(
            size: 20,
            trackColor: UiV2Theme.of(context).surface3,
            color: UiV2Theme.of(context).accent,
          ),
        ),
      ),
      error: (error, stack) => UiV2Empty(
        title: '歌单读取失败',
        // ignore: unnecessary_string_interpolations
        text: '$error',
        icon: UiV2Icons.info,
      ),
    );
  }
}

// ==================== 二次确认弹层 ====================

/// 打开二次确认（原型 openConfirm）
Future<void> showConfirmSheet(
  BuildContext context, {
  required String title,
  required String text,
  required String confirmLabel,
  required VoidCallback onConfirm,
}) {
  return showUiV2Sheet(
    context,
    title: title,
    child: Builder(
      builder: (context) {
        final t = UiV2Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(text, style: UiV2Text.bodyDim.copyWith(color: t.textDim)),
            const SizedBox(height: UiV2Spacing.s5),
            Row(
              children: [
                Expanded(
                  child: UiV2Button(
                    label: '取消',
                    variant: UiV2ButtonVariant.soft,
                    block: true,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ),
                const SizedBox(width: UiV2Spacing.s3),
                Expanded(
                  child: UiV2Button(
                    label: confirmLabel,
                    variant: UiV2ButtonVariant.danger,
                    block: true,
                    onTap: () {
                      onConfirm();
                      Navigator.of(context).maybePop();
                    },
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}
