/// ui 包 —— 回响播放器 UI 模块
///
/// 提供完整的 Flutter UI：主题系统、Riverpod 状态管理、页面、组件。
/// 壳工程通过 ProviderScope.overrides 注入服务实例。

// 主题系统
export 'src/theme/app_spacing.dart';
export 'src/theme/app_radius.dart';
export 'src/theme/app_theme.dart';

// 状态管理
export 'src/providers/providers.dart';

// 服务
export 'src/services/playlist_io.dart';

// 组件
export 'src/widgets/song_tile.dart';
export 'src/widgets/empty_state.dart';
export 'src/widgets/mini_player.dart';
export 'src/widgets/download_button.dart';
export 'src/widgets/lyrics_view.dart';
export 'src/widgets/color_picker_dialog.dart';
export 'src/widgets/cover_background.dart';
export 'src/widgets/pressable_scale.dart';
export 'src/widgets/scrollable_text.dart';
export 'src/widgets/player_overlay.dart';
export 'src/widgets/queue_sheet.dart';
export 'src/widgets/queue_song_row.dart';
export 'src/widgets/cover_image.dart';
export 'src/widgets/shimmer_box.dart';
export 'src/widgets/horizontal_fade.dart';

// 页面
export 'src/pages/app_shell.dart';
export 'src/pages/search_page.dart';
export 'src/pages/discover_page.dart';
export 'src/pages/player_page.dart';
export 'src/pages/recent_plays_page.dart';
export 'src/pages/playlist_list_page.dart';
export 'src/pages/playlist_detail_page.dart';
export 'src/pages/source_management_page.dart';
export 'src/pages/settings_page.dart';
export 'src/pages/download_queue_page.dart';
export 'src/pages/source_log_page.dart';
export 'src/pages/queue_page.dart';
export 'src/pages/artist_page.dart';
export 'src/pages/album_page.dart';
