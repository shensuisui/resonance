/// 全部歌单（原型 renderPlaylists）—— 数据来自真实歌单表（PlaylistDao）
library;

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/rows.dart';
import '../components/sheets.dart';
import '../components/surfaces.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../providers/providers.dart';
import '../router.dart';
import '../widgets/page_shell.dart';
import '../widgets/track_actions.dart';

/// 全部歌单页
class PlaylistsPage extends ConsumerWidget {
  /// 构造页面
  const PlaylistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 「全部歌单」只列自建歌单
    final async = ref.watch(ownedPlaylistsProvider);

    return PageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHead(
            title: '全部歌单',
            sub: '自建歌单保存在本地数据库，随 App 保留。',
            action: UiV2Button(
              label: '新建歌单',
              icon: UiV2Icons.plus,
              variant: UiV2ButtonVariant.soft,
              onTap: () => showNewPlaylistSheet(context),
            ),
          ),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(UiV2Spacing.s8),
              child: Center(child: UiV2Spinner(trackColor: Color(0x33FFFFFF), color: Color(0xFFFF5A3C), size: 24)),
            ),
            error: (e, _) => UiV2Panel(
              child: UiV2Empty(
                title: '歌单读取失败',
                text: '$e',
                icon: UiV2Icons.info,
              ),
            ),
            data: (playlists) {
              if (playlists.isEmpty) {
                return UiV2Panel(
                  child: UiV2Empty(
                    title: '还没有歌单',
                    text: '点右上角新建一个歌单，把喜欢的歌收进去。',
                    icon: UiV2Icons.queue,
                  ),
                );
              }
              return UiV2Section(
                title: '我的歌单（${playlists.length}）',
                child: UiV2CardGrid(
                  children: [
                    for (final playlist in playlists)
                      _PlaylistGridCard(playlist: playlist),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 单张歌单卡：封面拼贴取歌单快照里的封面，曲目数用 songKeys 长度
class _PlaylistGridCard extends ConsumerWidget {
  /// 目标歌单
  final Playlist playlist;

  /// 构造卡片
  const _PlaylistGridCard({required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final covers = playlist.songKeys
        .map((k) => playlist.songSnapshots[k]?.coverUrl)
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .take(4)
        .toList();
    return UiV2PlaylistCard(
      playlist: playlist,
      covers: covers,
      subtitle: '${playlist.songKeys.length} 首',
      width: double.infinity,
      owned: true,
      onTap: () => ref.read(navProvider.notifier).go('playlist', playlist.id),
      onPlay: () async {
        // 播放整张歌单：快照优先，缺元数据的回源补
        final songs = await ref.read(playlistActionsProvider).songsOf(playlist);
        if (!context.mounted) return;
        await TrackActions.playAll(context, ref, songs);
      },
    );
  }
}

/// 新建歌单弹层（原型 openNewPlaylistSheet）
Future<void> showNewPlaylistSheet(BuildContext context) {
  return showUiV2Sheet(
    context,
    title: '新建歌单',
    child: const UiV2NewPlaylistBody(),
  );
}

/// 新建歌单表单
class UiV2NewPlaylistBody extends StatefulWidget {
  /// 构造表单
  const UiV2NewPlaylistBody({super.key});

  @override
  State<UiV2NewPlaylistBody> createState() => _UiV2NewPlaylistBodyState();
}

class _UiV2NewPlaylistBodyState extends State<UiV2NewPlaylistBody> {
  final TextEditingController _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = UiV2Theme.of(context);
    return Consumer(
      builder: (context, ref, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('歌单名称', style: UiV2Text.buttonSmall.copyWith(color: t.text)),
            const SizedBox(height: 6),
            TextField(
              controller: _name,
              maxLength: 24,
              autofocus: true,
              style: UiV2Text.body.copyWith(color: t.text),
              decoration: InputDecoration(
                counterText: '',
                hintText: '例如：周末早晨',
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
                focusedBorder: OutlineInputBorder(
                  borderRadius: UiV2Radii.brMd,
                  borderSide: BorderSide(color: t.accent),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: UiV2Text.hint.copyWith(color: t.accent)),
            ],
            const SizedBox(height: UiV2Spacing.s4),
            UiV2Button(
              label: '创建歌单',
              icon: UiV2Icons.check,
              variant: UiV2ButtonVariant.primary,
              block: true,
              onTap: () async {
                final name = _name.text.trim();
                if (name.isEmpty) {
                  setState(() => _error = '请输入歌单名称');
                  return;
                }
                final id = await ref.read(playlistActionsProvider).create(name);
                if (!context.mounted) return;
                Navigator.of(context).maybePop();
                showUiV2Toast(context, '已创建歌单「$name」');
                ref.read(navProvider.notifier).go('playlist', id);
              },
            ),
          ],
        );
      },
    );
  }
}
