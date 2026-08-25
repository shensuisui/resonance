# S2：UI 与用户体验

| 状态 | 进行中 |
|:---|:---|
| 涉及包 | ui（新建）, fm_app（接入） |

---

## 1. 主题系统（禁止魔法值）

### 1.1 AppSpacing — 预定义间距静态值

```dart
class AppSpacing {
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s48 = 48;
  static const double s64 = 64;
}
```

所有 padding/margin/gap 使用 `AppSpacing.sX`，禁止内联数字。

### 1.2 AppRadius — 圆角静态值

```dart
class AppRadius {
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s24 = 24;
  static const double full = 999; // 圆形
}
```

### 1.3 AppTheme — 可切换亮/暗主题

```dart
class AppTheme {
  static ThemeData light() => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
    useMaterial3: true,
  );
  static ThemeData dark() => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.deepPurple, brightness: Brightness.dark),
    useMaterial3: true,
  );
}
```

所有颜色通过 `Theme.of(context).colorScheme` 获取，禁止硬编码颜色。

### 1.4 主题持久化

主题模式（light/dark/system）通过 `SettingsDao` 存储在 settings 表中，key = `theme_mode`。

---

## 2. Riverpod 状态管理

### 2.1 Provider 清单

| Provider | 类型 | 职责 |
|:---|:---|:---|
| `databaseProvider` | Provider | 全局 DatabaseProvider 实例 |
| `sourceManagerProvider` | Provider | 全局 SourceManager |
| `playerProvider` | Provider | Player 实例 |
| `recentPlaysServiceProvider` | Provider | RecentPlaysService |
| `downloadManagerProvider` | Provider | DownloadManager |
| `settingsServiceProvider` | Provider | SettingsDao |
| `themeModeProvider` | StateNotifierProvider | 主题模式（light/dark/system） |
| `searchNotifierProvider` | StateNotifierProvider | 搜索关键词 + 结果列表 |
| `recentPlaysNotifierProvider` | StateNotifierProvider | 最近播放列表 |
| `favoritesNotifierProvider` | StateNotifierProvider | 收藏列表 |
| `playlistNotifierProvider` | StateNotifierProvider | 歌单 CRUD |
| `downloadNotifierProvider` | StreamProvider | 下载任务流 |
| `playerStateProvider` | StreamProvider | 播放器状态流 |

### 2.2 初始化

在 fm_app 的 main() 中初始化所有服务，通过 `ProviderScope.overrides` 注入。

---

## 3. 页面结构

```
ShellApp (Scaffold + 底部导航 + 迷你播放器)
├── 搜索页 (SearchPage)
│   ├── 搜索框
│   ├── 搜索结果列表（跨源聚合）
│   └── 分页加载
├── 最近播放页 (RecentPlaysPage)
│   └── 歌曲列表（点击播放）
├── 歌单页 (PlaylistListPage → PlaylistDetailPage)
│   ├── 歌单列表
│   ├── 歌单详情（曲目列表）
│   └── 创建/编辑/删除
├── 源管理页 (SourceManagementPage)
│   └── 源列表 + 启用/禁用开关
└── 设置页 (SettingsPage)
    ├── 主题切换
    ├── 本地扫描目录配置
    └── 关于
```

### 3.1 迷你播放器

底部导航上方悬浮，显示当前歌曲、播放/暂停、进度条。点击展开为全屏播放页。

---

## 4. 文件结构

```
packages/ui/lib/
├── ui.dart
├── src/
│   ├── theme/
│   │   ├── app_spacing.dart
│   │   ├── app_radius.dart
│   │   └── app_theme.dart
│   ├── providers/
│   │   ├── providers.dart       # 所有 provider
│   │   ├── search_notifier.dart
│   │   ├── recent_plays_notifier.dart
│   │   ├── favorites_notifier.dart
│   │   ├── playlist_notifier.dart
│   │   └── theme_notifier.dart
│   ├── pages/
│   │   ├── app_shell.dart
│   │   ├── search_page.dart
│   │   ├── player_page.dart
│   │   ├── recent_plays_page.dart
│   │   ├── playlist_list_page.dart
│   │   ├── playlist_detail_page.dart
│   │   ├── source_management_page.dart
│   │   └── settings_page.dart
│   ├── widgets/
│   │   ├── mini_player.dart
│   │   ├── song_tile.dart
│   │   └── empty_state.dart
│   └── router/
│       └── app_router.dart
```
