/// 备份导入导出的界面流程测试（真实 DAO + 真实页面，只把「文件选择」换成假件）
///
/// 覆盖：
///   * 设置页「导出」把整包 JSON 交给 picker，并记录 last_backup；
///   * 「从文件导入」走预览 -> 确认 -> 落库（合并模式）；
///   * 非法文件给出提示且不动数据；
///   * 旧版单歌单文件可导入；
///   * 系统「用回响打开」事件到达时自动弹出导入预览。
library;

import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:portable/portable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:uiv2/src/app_router.dart';
import 'package:uiv2/uiv2.dart';

/// 假文件交互：记住被保存的内容、按预设返回「打开的文件」
class _FakePickers implements FilePickers {
  String? openContent;
  List<int>? openBytes;
  String? savedContent;
  List<int>? savedBytes;
  String? savedName;

  final StreamController<OpenedFile> _opened =
      StreamController<OpenedFile>.broadcast();

  @override
  Stream<OpenedFile> get openedFiles => _opened.stream;

  /// 模拟系统「用回响打开」
  void openFromSystem(String path, String content) =>
      _opened.add(OpenedFile(path: path, content: content));

  @override
  Future<String?> pickOpenFile({
    String title = '选择文件',
    List<String> extensions = const <String>[],
  }) async =>
      (openContent == null && openBytes == null) ? null : '/fake/backup.zip';

  @override
  Future<String?> readTextFile(String path) async => openContent;

  @override
  Future<List<int>?> readBinaryFile(String path) async =>
      openBytes ?? (openContent == null ? null : utf8.encode(openContent!));

  @override
  Future<String?> saveBinaryFile({
    required String title,
    String? suggestedName,
    List<String> extensions = const <String>[],
    required List<int> bytes,
  }) async {
    savedBytes = bytes;
    savedName = suggestedName;
    return '/fake/out/' + (suggestedName ?? 'backup.zip');
  }

  @override
  Future<String?> saveTextFile({
    required String title,
    String? suggestedName,
    List<String> extensions = const <String>[],
    required String content,
  }) async {
    savedContent = content;
    savedName = suggestedName;
    return '/fake/out/' + (suggestedName ?? 'backup.json');
  }
}

/// 手写假播放器（显式实现设置的读写：设置页会恢复播放模式与音量）
class _FakePlayer implements Player {
  @override
  Stream<PlayerState> get stateStream => const Stream.empty();
  @override
  Stream<int> get positionStream => const Stream.empty();
  @override
  Stream<int> get durationStream => const Stream.empty();
  @override
  PlayerState get currentState => PlayerState.idle;
  @override
  int get currentPosition => 0;
  @override
  int get currentDuration => 0;
  @override
  double volume = 1;
  @override
  PlayMode playMode = PlayMode.listLoop;
  @override
  List<Song> get queue => const <Song>[];
  @override
  int get currentIndex => -1;
  @override
  void setQueue(List<Song> songs) {}
  @override
  Future<void> play(Song song) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double value) async {}
  @override
  Future<void> next() async {}
  @override
  Future<void> previous() async {}
  @override
  Future<void> jumpToIndex(int index) async {}
  @override
  Future<void> prepareAt(int index, {Duration position = Duration.zero}) async {}
  @override
  Future<void> dispose() async {}
}

/// 假播放缓存
class _FakeCache implements AudioCache {
  @override
  Future<void> init() async {}
  @override
  Set<String> get cachedKeys => const {};
  @override
  bool isCached(String songKey) => false;
  @override
  String? localUrlFor(String songKey) => null;
  @override
  Future<String?> downloadedUrlFor(Song song) async => null;
  @override
  Future<void> cacheAfterPlay(Song song, String url,
      {Map<String, String>? headers}) async {}
  @override
  Future<int> sizeOnDisk() async => 0;
  @override
  Future<void> clear() async {}
  @override
  Stream<void> get changes => const Stream.empty();
}

/// 一份可导入的备份文本（一个歌单、两首歌）
String backupText() {
  final at = DateTime.utc(2026, 11, 12, 20, 30);
  final ms = at.millisecondsSinceEpoch;
  final id = legacyPlaylistIdForName('导入测试');
  return BackupCodec.encode(BackupDocument(
    exportedAt: at,
    deviceId: 'test',
    entities: <String, List<SyncRecord>>{
      SyncEntity.playlists: <SyncRecord>[
        SyncRecord(
          key: id,
          updatedAt: ms,
          deviceId: 'test',
          data: <String, Object?>{
            'id': id,
            'name': '导入测试',
            'songKeys': <String>['gequbao:1', 'gequbao:2'],
            'snapshots': <String, Object?>{
              'gequbao:1': <String, Object?>{'title': '素颜', 'artist': '许嵩'},
              'gequbao:2': <String, Object?>{'title': '幻听', 'artist': '许嵩'},
            },
          },
        ),
      ],
      SyncEntity.favorites: <SyncRecord>[
        SyncRecord(
          key: 'gequbao:1',
          updatedAt: ms,
          deviceId: 'test',
          data: <String, Object?>{'songKey': 'gequbao:1', 'time': ms},
        ),
      ],
    },
  ));
}

/// 多次 pump 代替 pumpAndSettle（页面里有持续动画，settle 会超时）
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late InMemoryDatabaseProvider db;
  late _FakePickers pickers;
  late ProviderContainer container;

  Future<void> bootstrap() async {
    db = InMemoryDatabaseProvider();
    await db.initialize();
    pickers = _FakePickers();
    container = ProviderContainer(overrides: <Override>[
      appDatabaseProvider.overrideWithValue(db),
      playerProvider.overrideWithValue(_FakePlayer()),
      sourceManagerProvider.overrideWithValue(SourceManager()),
      audioCacheProvider.overrideWithValue(_FakeCache()),
      recentPlaysServiceProvider
          .overrideWithValue(RecentPlaysService(db.recentPlaysDao)),
      filePickersProvider.overrideWithValue(pickers),
    ]);
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: container.read(appRouterProvider),
        theme: UiV2DesignTheme.dark(),
        builder: (context, c) =>
            c == null ? const SizedBox() : UiV2Scope(child: c),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> gotoBackupSection(WidgetTester tester) async {
    container.read(navProvider.notifier).go('settings');
    await _settle(tester);
    // 备份区块在设置页靠下，先滚到可见
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('settings_backup_export')),
      find.byType(SingleChildScrollView).last,
      const Offset(0, -200),
    );
    await tester.pump();
  }

  tearDown(() => container.dispose());

  testWidgets('设置页「导出全部数据」：把整包 JSON 交给 picker 并记录 last_backup', (tester) async {
    await bootstrap();
    await db.playlistDao.insertPlaylist(Playlist(
      id: 'p1',
      name: '夜行',
      songKeys: const <String>['gequbao:1'],
      createdTime: DateTime(2026, 1, 1),
      modifiedTime: DateTime(2026, 1, 1),
    ));
    await pumpApp(tester);
    await gotoBackupSection(tester);

    await tester.tap(find.byKey(const ValueKey('settings_backup_export_btn')));
    await _settle(tester);
    // 导出选项弹层 → 开始导出
    await tester.tap(find.text('开始导出'));
    await _settle(tester);

    expect(pickers.savedBytes, isNotNull);
    expect(pickers.savedBytes!.isNotEmpty, isTrue);
    expect(pickers.savedName, endsWith('.zip'));
    final lastBackup = await db.settingsDao.get('last_backup');
    expect(lastBackup, isNotNull);
    expect(lastBackup!, contains('"playlists":1'));
    // 消化 toast 的 2.2s 定时器，避免测试结束时报「Timer still pending」
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('「从文件导入」：预览 -> 开始导入 -> 歌单与收藏落库', (tester) async {
    await bootstrap();
    pickers.openContent = backupText();
    await pumpApp(tester);
    await gotoBackupSection(tester);

    await tester.tap(find.byKey(const ValueKey('settings_backup_import_btn')));
    await _settle(tester);

    expect(find.text('导入备份'), findsOneWidget, reason: '要先给预览，不能直接写库');
    expect(find.textContaining('1 个歌单 / 2 首'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import_confirm')));
    await _settle(tester);

    final playlists = await db.playlistDao.getAllPlaylists();
    expect(playlists.map((p) => p.name).toList(), contains('导入测试'));
    expect((await db.favoritesDao.getAllFavoriteRecords()).length, 1);
    // 消化 toast 的 2.2s 定时器，避免测试结束时报「Timer still pending」
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('非法文件：给出提示，数据一条不动', (tester) async {
    await bootstrap();
    pickers.openContent = 'definitely not json';
    await pumpApp(tester);
    await gotoBackupSection(tester);

    await tester.tap(find.byKey(const ValueKey('settings_backup_import_btn')));
    await _settle(tester);

    expect(find.textContaining('不是有效的备份文件'), findsOneWidget);
    expect(await db.playlistDao.getAllPlaylists(), isEmpty);
    // 消化 toast 的 2.2s 定时器，避免测试结束时报「Timer still pending」
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('旧版单歌单文件：预览标明旧版，导入后生成歌单', (tester) async {
    await bootstrap();
    pickers.openContent = jsonEncode(<String, dynamic>{
      'name': '老歌单',
      'songs': <Map<String, dynamic>>[
        <String, dynamic>{
          'title': '晴天',
          'artist': '周杰伦',
          'url': 'http://example.com/a.mp3',
        },
      ],
    });
    await pumpApp(tester);
    await gotoBackupSection(tester);

    await tester.tap(find.byKey(const ValueKey('settings_backup_import_btn')));
    await _settle(tester);

    expect(find.textContaining('旧版单歌单文件'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('import_confirm')));
    await _settle(tester);

    final playlists = await db.playlistDao.getAllPlaylists();
    expect(playlists.single.name, '老歌单');
    expect(playlists.single.songKeys.single, startsWith('local_custom:'));
    // 消化 toast 的 2.2s 定时器，避免测试结束时报「Timer still pending」
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('系统「用回响打开」事件到达 → 自动弹出导入预览', (tester) async {
    await bootstrap();
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const UiV2App(),
    ));
    await tester.pump(const Duration(milliseconds: 600));

    pickers.openFromSystem('/storage/downloads/backup.json', backupText());
    await _settle(tester);

    expect(find.text('导入备份'), findsOneWidget,
        reason: '打开 json 后应直接进入导入预览');
    // 消化 toast 的 2.2s 定时器，避免测试结束时报「Timer still pending」
    await tester.pump(const Duration(seconds: 3));
  });
}
