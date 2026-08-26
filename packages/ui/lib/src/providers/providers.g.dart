// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 数据库提供者
///
/// 函数名避开 `database`：生成类名会是 DatabaseProvider，与 core 同名抽象类冲突。

@ProviderFor(appDatabase)
final appDatabaseProvider = AppDatabaseProvider._();

/// 数据库提供者
///
/// 函数名避开 `database`：生成类名会是 DatabaseProvider，与 core 同名抽象类冲突。

final class AppDatabaseProvider
    extends
        $FunctionalProvider<
          DatabaseProvider,
          DatabaseProvider,
          DatabaseProvider
        >
    with $Provider<DatabaseProvider> {
  /// 数据库提供者
  ///
  /// 函数名避开 `database`：生成类名会是 DatabaseProvider，与 core 同名抽象类冲突。
  AppDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appDatabaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appDatabaseHash();

  @$internal
  @override
  $ProviderElement<DatabaseProvider> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DatabaseProvider create(Ref ref) {
    return appDatabase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DatabaseProvider value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DatabaseProvider>(value),
    );
  }
}

String _$appDatabaseHash() => r'12d67542a7ba78c45d564462362a74ffae4af1e8';

/// 源管理器

@ProviderFor(sourceManager)
final sourceManagerProvider = SourceManagerProvider._();

/// 源管理器

final class SourceManagerProvider
    extends $FunctionalProvider<SourceManager, SourceManager, SourceManager>
    with $Provider<SourceManager> {
  /// 源管理器
  SourceManagerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sourceManagerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sourceManagerHash();

  @$internal
  @override
  $ProviderElement<SourceManager> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SourceManager create(Ref ref) {
    return sourceManager(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SourceManager value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SourceManager>(value),
    );
  }
}

String _$sourceManagerHash() => r'd058e86c4cbd14da6c360fe775db4e7138b1404a';

/// 最近播放服务

@ProviderFor(recentPlaysService)
final recentPlaysServiceProvider = RecentPlaysServiceProvider._();

/// 最近播放服务

final class RecentPlaysServiceProvider
    extends
        $FunctionalProvider<
          RecentPlaysService,
          RecentPlaysService,
          RecentPlaysService
        >
    with $Provider<RecentPlaysService> {
  /// 最近播放服务
  RecentPlaysServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recentPlaysServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recentPlaysServiceHash();

  @$internal
  @override
  $ProviderElement<RecentPlaysService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RecentPlaysService create(Ref ref) {
    return recentPlaysService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RecentPlaysService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RecentPlaysService>(value),
    );
  }
}

String _$recentPlaysServiceHash() =>
    r'b7653df859ac3669fad292d38868c52a1a20edca';

/// 播放器接口（fm_app override 为 PlayerImpl）

@ProviderFor(player)
final playerProvider = PlayerProvider._();

/// 播放器接口（fm_app override 为 PlayerImpl）

final class PlayerProvider extends $FunctionalProvider<Player, Player, Player>
    with $Provider<Player> {
  /// 播放器接口（fm_app override 为 PlayerImpl）
  PlayerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playerHash();

  @$internal
  @override
  $ProviderElement<Player> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Player create(Ref ref) {
    return player(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Player value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Player>(value),
    );
  }
}

String _$playerHash() => r'2190a674d680e8b09b19b5e6ad3df1b2efbbc099';

/// 下载管理器（fm_app override 为 DownloadManagerImpl）

@ProviderFor(downloadManager)
final downloadManagerProvider = DownloadManagerProvider._();

/// 下载管理器（fm_app override 为 DownloadManagerImpl）

final class DownloadManagerProvider
    extends
        $FunctionalProvider<DownloadManager, DownloadManager, DownloadManager>
    with $Provider<DownloadManager> {
  /// 下载管理器（fm_app override 为 DownloadManagerImpl）
  DownloadManagerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'downloadManagerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$downloadManagerHash();

  @$internal
  @override
  $ProviderElement<DownloadManager> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DownloadManager create(Ref ref) {
    return downloadManager(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DownloadManager value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DownloadManager>(value),
    );
  }
}

String _$downloadManagerHash() => r'8e99735223b026301ae12a0bb0c904a332379964';

@ProviderFor(songDao)
final songDaoProvider = SongDaoProvider._();

final class SongDaoProvider
    extends $FunctionalProvider<SongDao, SongDao, SongDao>
    with $Provider<SongDao> {
  SongDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'songDaoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$songDaoHash();

  @$internal
  @override
  $ProviderElement<SongDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SongDao create(Ref ref) {
    return songDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SongDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SongDao>(value),
    );
  }
}

String _$songDaoHash() => r'b0e5a5740aba9393daa1cd6012b6aa77ec6f3163';

@ProviderFor(settingsDao)
final settingsDaoProvider = SettingsDaoProvider._();

final class SettingsDaoProvider
    extends $FunctionalProvider<SettingsDao, SettingsDao, SettingsDao>
    with $Provider<SettingsDao> {
  SettingsDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsDaoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsDaoHash();

  @$internal
  @override
  $ProviderElement<SettingsDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SettingsDao create(Ref ref) {
    return settingsDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SettingsDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SettingsDao>(value),
    );
  }
}

String _$settingsDaoHash() => r'a0a5073bee4b1c7ab22a219c1b79798d6aef8421';

@ProviderFor(playlistDao)
final playlistDaoProvider = PlaylistDaoProvider._();

final class PlaylistDaoProvider
    extends $FunctionalProvider<PlaylistDao, PlaylistDao, PlaylistDao>
    with $Provider<PlaylistDao> {
  PlaylistDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playlistDaoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playlistDaoHash();

  @$internal
  @override
  $ProviderElement<PlaylistDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PlaylistDao create(Ref ref) {
    return playlistDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlaylistDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlaylistDao>(value),
    );
  }
}

String _$playlistDaoHash() => r'725ef351784f02d35f9d664f44d033bf463dd884';

@ProviderFor(favoritesDao)
final favoritesDaoProvider = FavoritesDaoProvider._();

final class FavoritesDaoProvider
    extends $FunctionalProvider<FavoritesDao, FavoritesDao, FavoritesDao>
    with $Provider<FavoritesDao> {
  FavoritesDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'favoritesDaoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$favoritesDaoHash();

  @$internal
  @override
  $ProviderElement<FavoritesDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  FavoritesDao create(Ref ref) {
    return favoritesDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FavoritesDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FavoritesDao>(value),
    );
  }
}

String _$favoritesDaoHash() => r'309e9ef1596e1300d9c1efdb6adc7e42c701a25b';

/// 下载任务流（来自 DownloadManager）

@ProviderFor(downloadTasks)
final downloadTasksProvider = DownloadTasksProvider._();

/// 下载任务流（来自 DownloadManager）

final class DownloadTasksProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<DownloadTask>>,
          List<DownloadTask>,
          Stream<List<DownloadTask>>
        >
    with
        $FutureModifier<List<DownloadTask>>,
        $StreamProvider<List<DownloadTask>> {
  /// 下载任务流（来自 DownloadManager）
  DownloadTasksProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'downloadTasksProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$downloadTasksHash();

  @$internal
  @override
  $StreamProviderElement<List<DownloadTask>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<DownloadTask>> create(Ref ref) {
    return downloadTasks(ref);
  }
}

String _$downloadTasksHash() => r'2629cc1ccfaab032417fd20ea7731db0e5f4864d';

/// 歌曲是否已收藏

@ProviderFor(isFavorite)
final isFavoriteProvider = IsFavoriteFamily._();

/// 歌曲是否已收藏

final class IsFavoriteProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// 歌曲是否已收藏
  IsFavoriteProvider._({
    required IsFavoriteFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'isFavoriteProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$isFavoriteHash();

  @override
  String toString() {
    return r'isFavoriteProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    final argument = this.argument as String;
    return isFavorite(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is IsFavoriteProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$isFavoriteHash() => r'696441ff0c52e30e8dfa3737463862941d93d73b';

/// 歌曲是否已收藏

final class IsFavoriteFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<bool>, String> {
  IsFavoriteFamily._()
    : super(
        retry: null,
        name: r'isFavoriteProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// 歌曲是否已收藏

  IsFavoriteProvider call(String songKey) =>
      IsFavoriteProvider._(argument: songKey, from: this);

  @override
  String toString() => r'isFavoriteProvider';
}

/// 播放控制器 —— 统一播放入口
///
/// 取播放 URL → 播放 → 同步 UI 状态 → 记录最近播放。
/// 所有页面通过此入口播放，避免重复逻辑、保证队列状态一致。

@ProviderFor(PlaybackController)
final playbackControllerProvider = PlaybackControllerProvider._();

/// 播放控制器 —— 统一播放入口
///
/// 取播放 URL → 播放 → 同步 UI 状态 → 记录最近播放。
/// 所有页面通过此入口播放，避免重复逻辑、保证队列状态一致。
final class PlaybackControllerProvider
    extends $NotifierProvider<PlaybackController, void> {
  /// 播放控制器 —— 统一播放入口
  ///
  /// 取播放 URL → 播放 → 同步 UI 状态 → 记录最近播放。
  /// 所有页面通过此入口播放，避免重复逻辑、保证队列状态一致。
  PlaybackControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playbackControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playbackControllerHash();

  @$internal
  @override
  PlaybackController create() => PlaybackController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$playbackControllerHash() =>
    r'bb12054caa08a5f623a8577192aad86c8f633d35';

/// 播放控制器 —— 统一播放入口
///
/// 取播放 URL → 播放 → 同步 UI 状态 → 记录最近播放。
/// 所有页面通过此入口播放，避免重复逻辑、保证队列状态一致。

abstract class _$PlaybackController extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 播放器状态流绑定 —— 底层播放器流同步到 UI 状态 Provider
///
/// 在 AppShell 中 watch 一次即可保持应用生命周期内生效：
/// 进度条、歌词同步、播放/暂停按钮状态都依赖此绑定。

@ProviderFor(playerStreamBinding)
final playerStreamBindingProvider = PlayerStreamBindingProvider._();

/// 播放器状态流绑定 —— 底层播放器流同步到 UI 状态 Provider
///
/// 在 AppShell 中 watch 一次即可保持应用生命周期内生效：
/// 进度条、歌词同步、播放/暂停按钮状态都依赖此绑定。

final class PlayerStreamBindingProvider
    extends $FunctionalProvider<void, void, void>
    with $Provider<void> {
  /// 播放器状态流绑定 —— 底层播放器流同步到 UI 状态 Provider
  ///
  /// 在 AppShell 中 watch 一次即可保持应用生命周期内生效：
  /// 进度条、歌词同步、播放/暂停按钮状态都依赖此绑定。
  PlayerStreamBindingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playerStreamBindingProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playerStreamBindingHash();

  @$internal
  @override
  $ProviderElement<void> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  void create(Ref ref) {
    return playerStreamBinding(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$playerStreamBindingHash() =>
    r'd1908f391eb22244956351116355dd98ce04297f';

/// 当前播放歌曲

@ProviderFor(CurrentSong)
final currentSongProvider = CurrentSongProvider._();

/// 当前播放歌曲
final class CurrentSongProvider extends $NotifierProvider<CurrentSong, Song?> {
  /// 当前播放歌曲
  CurrentSongProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentSongProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentSongHash();

  @$internal
  @override
  CurrentSong create() => CurrentSong();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Song? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Song?>(value),
    );
  }
}

String _$currentSongHash() => r'3a3fe71fcc2439a22c12678e067387969de7da9b';

/// 当前播放歌曲

abstract class _$CurrentSong extends $Notifier<Song?> {
  Song? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Song?, Song?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Song?, Song?>,
              Song?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 播放队列

@ProviderFor(PlayQueue)
final playQueueProvider = PlayQueueProvider._();

/// 播放队列
final class PlayQueueProvider extends $NotifierProvider<PlayQueue, List<Song>> {
  /// 播放队列
  PlayQueueProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playQueueProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playQueueHash();

  @$internal
  @override
  PlayQueue create() => PlayQueue();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<Song> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<Song>>(value),
    );
  }
}

String _$playQueueHash() => r'31d959efc0c51438e96a5821cbc307eba3629ad0';

/// 播放队列

abstract class _$PlayQueue extends $Notifier<List<Song>> {
  List<Song> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<Song>, List<Song>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<Song>, List<Song>>,
              List<Song>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 是否正在播放

@ProviderFor(IsPlaying)
final isPlayingProvider = IsPlayingProvider._();

/// 是否正在播放
final class IsPlayingProvider extends $NotifierProvider<IsPlaying, bool> {
  /// 是否正在播放
  IsPlayingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'isPlayingProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$isPlayingHash();

  @$internal
  @override
  IsPlaying create() => IsPlaying();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$isPlayingHash() => r'e7d8e68c237d227070bbcfbf0b8b39cbd81155af';

/// 是否正在播放

abstract class _$IsPlaying extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 当前播放进度

@ProviderFor(PlaybackPosition)
final playbackPositionProvider = PlaybackPositionProvider._();

/// 当前播放进度
final class PlaybackPositionProvider
    extends $NotifierProvider<PlaybackPosition, Duration> {
  /// 当前播放进度
  PlaybackPositionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playbackPositionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playbackPositionHash();

  @$internal
  @override
  PlaybackPosition create() => PlaybackPosition();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Duration value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Duration>(value),
    );
  }
}

String _$playbackPositionHash() => r'1a23c32f41ab44236e7eeb1a906efc47e74ccb65';

/// 当前播放进度

abstract class _$PlaybackPosition extends $Notifier<Duration> {
  Duration build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Duration, Duration>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Duration, Duration>,
              Duration,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 总时长

@ProviderFor(PlaybackDuration)
final playbackDurationProvider = PlaybackDurationProvider._();

/// 总时长
final class PlaybackDurationProvider
    extends $NotifierProvider<PlaybackDuration, Duration> {
  /// 总时长
  PlaybackDurationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playbackDurationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playbackDurationHash();

  @$internal
  @override
  PlaybackDuration create() => PlaybackDuration();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Duration value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Duration>(value),
    );
  }
}

String _$playbackDurationHash() => r'b29881885f854997bf4e9acbb004abcb7711c96a';

/// 总时长

abstract class _$PlaybackDuration extends $Notifier<Duration> {
  Duration build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Duration, Duration>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Duration, Duration>,
              Duration,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 播放模式（持久化）

@ProviderFor(PlayModeNotifier)
final playModeProvider = PlayModeNotifierProvider._();

/// 播放模式（持久化）
final class PlayModeNotifierProvider
    extends $NotifierProvider<PlayModeNotifier, PlayMode> {
  /// 播放模式（持久化）
  PlayModeNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'playModeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$playModeNotifierHash();

  @$internal
  @override
  PlayModeNotifier create() => PlayModeNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlayMode value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlayMode>(value),
    );
  }
}

String _$playModeNotifierHash() => r'8af7f478230fcadcf4ae4d6853be0443e19be326';

/// 播放模式（持久化）

abstract class _$PlayModeNotifier extends $Notifier<PlayMode> {
  PlayMode build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PlayMode, PlayMode>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PlayMode, PlayMode>,
              PlayMode,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 主题模式状态

@ProviderFor(ThemeModeNotifier)
final themeModeProvider = ThemeModeNotifierProvider._();

/// 主题模式状态
final class ThemeModeNotifierProvider
    extends $NotifierProvider<ThemeModeNotifier, ThemeMode> {
  /// 主题模式状态
  ThemeModeNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'themeModeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$themeModeNotifierHash();

  @$internal
  @override
  ThemeModeNotifier create() => ThemeModeNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThemeMode value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThemeMode>(value),
    );
  }
}

String _$themeModeNotifierHash() => r'687e197b94a8a441dc295ef51446e460702b59bd';

/// 主题模式状态

abstract class _$ThemeModeNotifier extends $Notifier<ThemeMode> {
  ThemeMode build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ThemeMode, ThemeMode>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ThemeMode, ThemeMode>,
              ThemeMode,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 搜索 Notifier

@ProviderFor(SearchNotifier)
final searchProvider = SearchNotifierProvider._();

/// 搜索 Notifier
final class SearchNotifierProvider
    extends $NotifierProvider<SearchNotifier, SearchState> {
  /// 搜索 Notifier
  SearchNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'searchProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$searchNotifierHash();

  @$internal
  @override
  SearchNotifier create() => SearchNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SearchState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SearchState>(value),
    );
  }
}

String _$searchNotifierHash() => r'efc1e71d1e6081fb3714e8d731239a78e24b6315';

/// 搜索 Notifier

abstract class _$SearchNotifier extends $Notifier<SearchState> {
  SearchState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SearchState, SearchState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SearchState, SearchState>,
              SearchState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 最近播放列表

@ProviderFor(RecentPlaysNotifier)
final recentPlaysProvider = RecentPlaysNotifierProvider._();

/// 最近播放列表
final class RecentPlaysNotifierProvider
    extends $NotifierProvider<RecentPlaysNotifier, List<Song>> {
  /// 最近播放列表
  RecentPlaysNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recentPlaysProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recentPlaysNotifierHash();

  @$internal
  @override
  RecentPlaysNotifier create() => RecentPlaysNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<Song> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<Song>>(value),
    );
  }
}

String _$recentPlaysNotifierHash() =>
    r'5cb629c3257b8f61cc2e050a8b8cbe3180b6e022';

/// 最近播放列表

abstract class _$RecentPlaysNotifier extends $Notifier<List<Song>> {
  List<Song> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<Song>, List<Song>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<Song>, List<Song>>,
              List<Song>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 收藏列表

@ProviderFor(FavoritesNotifier)
final favoritesProvider = FavoritesNotifierProvider._();

/// 收藏列表
final class FavoritesNotifierProvider
    extends $NotifierProvider<FavoritesNotifier, List<Song>> {
  /// 收藏列表
  FavoritesNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'favoritesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$favoritesNotifierHash();

  @$internal
  @override
  FavoritesNotifier create() => FavoritesNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<Song> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<Song>>(value),
    );
  }
}

String _$favoritesNotifierHash() => r'003db41185504d171df34e97cf9cfe66660cf055';

/// 收藏列表

abstract class _$FavoritesNotifier extends $Notifier<List<Song>> {
  List<Song> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<Song>, List<Song>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<Song>, List<Song>>,
              List<Song>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 已注册源列表

@ProviderFor(sourceList)
final sourceListProvider = SourceListProvider._();

/// 已注册源列表

final class SourceListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<MusicSource>>,
          List<MusicSource>,
          FutureOr<List<MusicSource>>
        >
    with
        $FutureModifier<List<MusicSource>>,
        $FutureProvider<List<MusicSource>> {
  /// 已注册源列表
  SourceListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sourceListProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sourceListHash();

  @$internal
  @override
  $FutureProviderElement<List<MusicSource>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<MusicSource>> create(Ref ref) {
    return sourceList(ref);
  }
}

String _$sourceListHash() => r'cf3c429dc5be29bd573881978d9fd00a47fb7427';

/// 源启用状态

@ProviderFor(SourceEnabled)
final sourceEnabledProvider = SourceEnabledProvider._();

/// 源启用状态
final class SourceEnabledProvider
    extends $NotifierProvider<SourceEnabled, Map<String, bool>> {
  /// 源启用状态
  SourceEnabledProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sourceEnabledProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sourceEnabledHash();

  @$internal
  @override
  SourceEnabled create() => SourceEnabled();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, bool> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, bool>>(value),
    );
  }
}

String _$sourceEnabledHash() => r'def98cc3a6874c2446b31cee425b9c0b3205f595';

/// 源启用状态

abstract class _$SourceEnabled extends $Notifier<Map<String, bool>> {
  Map<String, bool> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Map<String, bool>, Map<String, bool>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Map<String, bool>, Map<String, bool>>,
              Map<String, bool>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 本地扫描 Notifier

@ProviderFor(ScanNotifier)
final scanProvider = ScanNotifierProvider._();

/// 本地扫描 Notifier
final class ScanNotifierProvider
    extends $NotifierProvider<ScanNotifier, ScanState> {
  /// 本地扫描 Notifier
  ScanNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'scanProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$scanNotifierHash();

  @$internal
  @override
  ScanNotifier create() => ScanNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ScanState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ScanState>(value),
    );
  }
}

String _$scanNotifierHash() => r'a0cd6823807f38dd72440c46eb18554ba436be0c';

/// 本地扫描 Notifier

abstract class _$ScanNotifier extends $Notifier<ScanState> {
  ScanState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ScanState, ScanState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ScanState, ScanState>,
              ScanState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 发现页 Notifier —— 聚合各源的推荐歌单

@ProviderFor(DiscoverNotifier)
final discoverProvider = DiscoverNotifierProvider._();

/// 发现页 Notifier —— 聚合各源的推荐歌单
final class DiscoverNotifierProvider
    extends $NotifierProvider<DiscoverNotifier, DiscoverState> {
  /// 发现页 Notifier —— 聚合各源的推荐歌单
  DiscoverNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'discoverProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$discoverNotifierHash();

  @$internal
  @override
  DiscoverNotifier create() => DiscoverNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DiscoverState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DiscoverState>(value),
    );
  }
}

String _$discoverNotifierHash() => r'1ea5699dd5c9b1b06bfe12ffe5bbc23265d9e522';

/// 发现页 Notifier —— 聚合各源的推荐歌单

abstract class _$DiscoverNotifier extends $Notifier<DiscoverState> {
  DiscoverState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<DiscoverState, DiscoverState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DiscoverState, DiscoverState>,
              DiscoverState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 当前歌曲歌词（随 currentSong 变化自动加载）

@ProviderFor(LyricsNotifier)
final lyricsProvider = LyricsNotifierProvider._();

/// 当前歌曲歌词（随 currentSong 变化自动加载）
final class LyricsNotifierProvider
    extends $NotifierProvider<LyricsNotifier, Lyrics?> {
  /// 当前歌曲歌词（随 currentSong 变化自动加载）
  LyricsNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lyricsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lyricsNotifierHash();

  @$internal
  @override
  LyricsNotifier create() => LyricsNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Lyrics? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Lyrics?>(value),
    );
  }
}

String _$lyricsNotifierHash() => r'9ef7ea0b589bb230e682a5d217f1852390c5904a';

/// 当前歌曲歌词（随 currentSong 变化自动加载）

abstract class _$LyricsNotifier extends $Notifier<Lyrics?> {
  Lyrics? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Lyrics?, Lyrics?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Lyrics?, Lyrics?>,
              Lyrics?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// 插件库 Notifier —— 插件的加载/导入/下载与持久化
///
/// 插件文件统一存放在应用支持目录的 plugins/ 子目录，
/// 启动时自动加载（AppShell watch 触发），支持：
/// - 本地目录批量加载
/// - 从 URL 下载
/// - 从文件导入
/// - 加载 PRD 默认远程插件源（落雪 / MusicFree）

@ProviderFor(PluginLibrary)
final pluginLibraryProvider = PluginLibraryProvider._();

/// 插件库 Notifier —— 插件的加载/导入/下载与持久化
///
/// 插件文件统一存放在应用支持目录的 plugins/ 子目录，
/// 启动时自动加载（AppShell watch 触发），支持：
/// - 本地目录批量加载
/// - 从 URL 下载
/// - 从文件导入
/// - 加载 PRD 默认远程插件源（落雪 / MusicFree）
final class PluginLibraryProvider
    extends $NotifierProvider<PluginLibrary, PluginLibraryState> {
  /// 插件库 Notifier —— 插件的加载/导入/下载与持久化
  ///
  /// 插件文件统一存放在应用支持目录的 plugins/ 子目录，
  /// 启动时自动加载（AppShell watch 触发），支持：
  /// - 本地目录批量加载
  /// - 从 URL 下载
  /// - 从文件导入
  /// - 加载 PRD 默认远程插件源（落雪 / MusicFree）
  PluginLibraryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pluginLibraryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pluginLibraryHash();

  @$internal
  @override
  PluginLibrary create() => PluginLibrary();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PluginLibraryState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PluginLibraryState>(value),
    );
  }
}

String _$pluginLibraryHash() => r'90b48a5b1c9847793decb1d48a03f462c992b9ee';

/// 插件库 Notifier —— 插件的加载/导入/下载与持久化
///
/// 插件文件统一存放在应用支持目录的 plugins/ 子目录，
/// 启动时自动加载（AppShell watch 触发），支持：
/// - 本地目录批量加载
/// - 从 URL 下载
/// - 从文件导入
/// - 加载 PRD 默认远程插件源（落雪 / MusicFree）

abstract class _$PluginLibrary extends $Notifier<PluginLibraryState> {
  PluginLibraryState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PluginLibraryState, PluginLibraryState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PluginLibraryState, PluginLibraryState>,
              PluginLibraryState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
