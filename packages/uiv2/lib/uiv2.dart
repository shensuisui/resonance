/// uiv2 —— 音乐播放器 UI 模块 v2（「回响 Resonance」原型实现）
///
/// 设计目标：
///   * 视觉与布局严格对齐原型 assets/styles.css 的令牌与断点；
///   * 无第三方 UI 依赖、无代码生成，显式 Riverpod Provider，便于逐条对照原型 JS；
///   * 只消费 core / crawler / player / db 的抽象类型，业务状态全部走 Provider。
///
/// 壳工程用法：
/// ```dart
/// runApp(ProviderScope(
///   overrides: [
///     appDatabaseProvider.overrideWith((ref) => db),
///     sourceManagerProvider.overrideWith((ref) => sources),
///     playerProvider.overrideWith((ref) => player),
///     downloadManagerProvider.overrideWith((ref) => downloads),
///     recentPlaysServiceProvider.overrideWith((ref) => recent),
///   ],
///   child: const FmAppV2(),
/// ));
/// ```
library;

// 设计层
export 'src/design/icons.dart';
export 'src/design/motion.dart';
export 'src/design/network_image.dart';
export 'src/design/theme.dart';
export 'src/design/tokens.dart';
export 'src/design/typography.dart';

// 数据层
export 'src/data/catalog.dart';
export 'src/data/catalog_source.dart';
export 'src/data/lyrics.dart';

// 状态层
export 'src/providers/providers.dart';

// 路由与外壳
export 'src/router.dart';
export 'src/app.dart';
export 'src/pages/app_shell.dart';

// 通用组件
export 'src/components/hero.dart';
export 'src/components/now_playing.dart';
export 'src/components/player_bar.dart';
export 'src/components/rows.dart';
export 'src/components/sheets.dart';
export 'src/components/shell_parts.dart';
export 'src/components/surfaces.dart';
export 'src/widgets/page_shell.dart';
export 'src/widgets/track_actions.dart';

// 页面
export 'src/pages/album_page.dart';
export 'src/pages/artist_page.dart';
export 'src/pages/downloads_page.dart';
export 'src/pages/folder_page.dart';
export 'src/pages/home_page.dart';
export 'src/pages/library_page.dart';
export 'src/pages/liked_page.dart';
export 'src/pages/local_page.dart';
export 'src/pages/logs_page.dart';
export 'src/pages/playlist_page.dart';
export 'src/pages/playlists_page.dart';
export 'src/pages/profile_page.dart';
export 'src/pages/recent_page.dart';
export 'src/pages/search_page.dart';
export 'src/pages/settings_page.dart';
export 'src/pages/sources_page.dart';
export 'src/pages/subs_page.dart';
