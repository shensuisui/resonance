/// 我的（原型 renderProfile）：资料头 + 统计 + 歌单 + 播放与外观 + 音乐源与订阅 + 空间 + 关于。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/sheets.dart';
import '../components/surfaces.dart';
import '../data/catalog.dart' show kRecentMax;
import '../design/tokens.dart';
import '../design/typography.dart';
import '../providers/providers.dart';
import '../router.dart';
import '../widgets/page_shell.dart';

/// 我的
class ProfilePage extends ConsumerWidget {
  /// 构造页面
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiV2Theme.of(context);
    // 全部统计来自真实数据源：DAO / 服务 / 扫描缓存
    final likedCount = ref.watch(favoriteCountProvider);
    // 「我的歌单」只列自建歌单
    final playlistsAsync = ref.watch(ownedPlaylistsProvider);
    final playlists = playlistsAsync.value ?? const [];
    final topPlaylists = playlists.take(4).toList();
    final localCount = ref.watch(localTracksProvider).length;
    final recentCount = ref.watch(recentProvider).length;
    // 计数用「可管理的源」口径：内置能力（我最喜欢/本地音乐/自建歌曲）不算，
    // 否则会出现「4 个源 · 已启用 6 个」这种自相矛盾的数字
    final sources = ref.watch(manageableSourcesProvider);
    final enabledCount = ref.watch(enabledManageableSourcesProvider).length;
    final logs = ref.watch(sourceLogProvider).entries;
    final tasks = ref.watch(downloadTasksProvider).value ?? const [];

    return PageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 资料头（.profile-head）
          Padding(
            padding: const EdgeInsets.only(bottom: UiV2Spacing.s5),
            child: Row(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        t.accent,
                        Color.lerp(t.accent, t.surface3, 0.6) ?? t.surface3,
                      ],
                    ),
                    borderRadius: UiV2Radii.brPill,
                  ),
                  alignment: Alignment.center,
                  child: Text('响', style: UiV2Text.statNum.copyWith(color: t.accentInk)),
                ),
                const SizedBox(width: UiV2Spacing.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('听歌的人', style: UiV2Text.statNum.copyWith(color: t.text)),
                      Text(
                        '免费账户 · 在线与本地同步',
                        style: UiV2Text.bodyDim.copyWith(color: t.textDim),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 统计（.stats）
          Padding(
            padding: const EdgeInsets.only(bottom: UiV2Spacing.s6),
            child: Row(
              children: [
                Expanded(
                  child: UiV2Stat(
                    number: '${likedCount}',
                    caption: '喜欢的歌曲',
                    onTap: () => ref.read(navProvider.notifier).go('liked'),
                  ),
                ),
                const SizedBox(width: UiV2Spacing.s3),
                Expanded(
                  child: UiV2Stat(
                    number: '${playlists.length}',
                    caption: '歌单',
                    onTap: () => ref.read(navProvider.notifier).go('playlists'),
                  ),
                ),
                const SizedBox(width: UiV2Spacing.s3),
                Expanded(
                  child: UiV2Stat(
                    number: '${localCount}',
                    caption: '本地曲目',
                    onTap: () => ref.read(navProvider.notifier).go('local'),
                  ),
                ),
              ],
            ),
          ),
          // 我的歌单
          UiV2Section(
            title: '我的歌单',
            linkText: '全部歌单',
            onLinkTap: () => ref.read(navProvider.notifier).go('playlists'),
            child: UiV2Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < topPlaylists.length; i++)
                    UiV2ListRow(
                      label: topPlaylists[i].name,
                      hint: '${topPlaylists[i].songKeys.length} 首',
                      divider: i < topPlaylists.length - 1,
                      trailing: const UiV2Chevron(),
                      onTap: () => ref
                          .read(navProvider.notifier)
                          .go('playlist', topPlaylists[i].id),
                    ),
                ],
              ),
            ),
          ),
          // 播放与外观
          UiV2Section(
            title: '播放与外观',
            child: UiV2Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  UiV2ListRow(
                    label: '深色主题',
                    hint: '跟随你的选择，不影响播放',
                    trailing: UiV2Switch(
                      value: ref.watch(themeModeProvider) == ThemeMode.dark,
                      semanticLabel: '深色主题',
                      onChanged: (_) =>
                          ref.read(themeModeProvider.notifier).toggleDark(),
                    ),
                  ),
                  UiV2ListRow(
                    label: '仅 Wi-Fi 下载',
                    hint: '避免消耗手机流量',
                    divider: true,
                    trailing: UiV2Switch(
                      value: ref.watch(wifiOnlyProvider),
                      semanticLabel: '仅 Wi-Fi 下载',
                      onChanged: (value) async {
                        await ref.read(wifiOnlyProvider.notifier).set(value);
                        if (context.mounted) {
                          showUiV2Toast(
                            context,
                            value ? '仅 Wi-Fi 下载：已开启' : '仅 Wi-Fi 下载：已关闭',
                          );
                        }
                      },
                    ),
                  ),
                  // 设置入口：主题/播放模式/音量/扫描目录/数据清理都在独立设置页，
                  // 之前只注册了路由却没有任何入口，成了死页。
                  UiV2ListRow(
                    label: '设置',
                    hint: '主题、播放模式、音量、扫描目录与数据清理',
                    divider: false,
                    trailing: const UiV2Chevron(),
                    onTap: () => ref.read(navProvider.notifier).go('settings'),
                  ),
                ],
              ),
            ),
          ),
          // 音乐源与订阅
          UiV2Section(
            title: '音乐源与订阅',
            child: UiV2Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  UiV2ListRow(
                    label: '音乐源',
                    hint: '${sources.length} 个源 · 已启用 $enabledCount 个',
                    trailing: const UiV2Chevron(),
                    onTap: () => ref.read(navProvider.notifier).go('sources'),
                  ),
                  UiV2ListRow(
                    label: '订阅',
                    hint: '订阅会展开成 1~N 个音乐源',
                    trailing: const UiV2Chevron(),
                    onTap: () => ref.read(navProvider.notifier).go('subs'),
                  ),
                  UiV2ListRow(
                    label: '运行日志',
                    hint: logs.isEmpty ? '暂无记录' : '最近 ${logs.length} 条记录',
                    divider: false,
                    trailing: const UiV2Chevron(),
                    onTap: () => ref.read(navProvider.notifier).go('logs'),
                  ),
                ],
              ),
            ),
          ),
          // 空间
          UiV2Section(
            title: '空间',
            child: UiV2Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  UiV2ListRow(
                    label: '我喜欢的音乐',
                    hint: '$likedCount 首',
                    trailing: const UiV2Chevron(),
                    onTap: () => ref.read(navProvider.notifier).go('liked'),
                  ),
                  UiV2ListRow(
                    label: '本地音乐',
                    hint: '$localCount 首',
                    trailing: const UiV2Chevron(),
                    onTap: () => ref.read(navProvider.notifier).go('local'),
                  ),
                  UiV2ListRow(
                    label: '最近播放',
                    hint: '$recentCount 首 · 上限 $kRecentMax 首',
                    trailing: const UiV2Chevron(),
                    onTap: () => ref.read(navProvider.notifier).go('recent'),
                  ),
                  UiV2ListRow(
                    label: '已下载',
                    hint: '${tasks.length} 个下载任务',
                    trailing: UiV2GhostMini(
                      label: '管理',
                      onTap: () =>
                          ref.read(navProvider.notifier).go('downloads'),
                    ),
                  ),
                  UiV2ListRow(
                    label: '下载任务',
                    hint: tasks.isEmpty ? '没有下载任务' : '${tasks.length} 个任务',
                    divider: false,
                    trailing: const UiV2Chevron(),
                    onTap: () => ref.read(navProvider.notifier).go('downloads'),
                  ),
                ],
              ),
            ),
          ),
          // 关于
          UiV2Section(
            title: '关于',
            child: UiV2Panel(
              padding: EdgeInsets.zero,
              child: UiV2ListRow(
                label: '回响 Resonance',
                hint: '版本 1.0 · 响应式界面（uiv2）',
                divider: false,
                trailing: UiV2GhostMini(
                  label: '说明',
                  onTap: () => showAboutSheet(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 关于弹层（原型 openAbout）
Future<void> showAboutSheet(BuildContext context) {
  return showUiV2Sheet(
    context,
    title: '关于这个界面',
    child: const _AboutBody(),
  );
}

class _AboutBody extends StatelessWidget {
  const _AboutBody();

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    const paragraphs = [
      '同一套界面覆盖手机与大屏：窄屏用底部导航与顶栏，宽屏换成左侧导航，播放条三区自适应。',
      '演示曲库由本地 demo_source HTTP 服务提供（仅 Debug），封面、音频、歌词都不随 App 打包。',
      '歌词由音乐源提供；本地曲目会读取扫描时一同选中的同名 .lrc。',
      '播放模式、睡眠定时器、下载与缓存都在「我的」与播放队列里操作。',
      '喜欢、最近播放、搜索历史、主题、音量等状态保存在本地数据库，重启后恢复。',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final text in paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: UiV2Spacing.s3),
            child: Text(text, style: UiV2Text.bodyDim.copyWith(color: t.textDim)),
          ),
        const SizedBox(height: UiV2Spacing.s3),
        UiV2Button(
          label: '知道了',
          variant: UiV2ButtonVariant.primary,
          block: true,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}
