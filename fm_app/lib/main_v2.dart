/// fm 音乐播放器 — 壳工程入口（uiv2：「回响 Resonance」界面）
///
/// 职责：
/// 1. 初始化 SQLite 数据库（SqfliteDatabaseProvider）
/// 2. 创建 PlayerImpl 播放器
/// 3. 从 assets/rules/ 加载规则源
/// 4. 注册本地源 + 规则源到 SourceManager
/// 5. 通过 ProviderScope.overrides 注入服务到 UI 层（uiv2 状态层）
///
/// 与 main.dart 的唯一差别：UI 包换成 packages/uiv2。
///
/// 壳工程不写业务逻辑，只做组装。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flan_flutter/flan_flutter.dart';
import 'package:logging/logging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import 'package:crawler/crawler.dart';
import 'package:db/db.dart';
import 'package:player/player.dart';

import 'package:uiv2/uiv2.dart';
import 'config/agent_debug_config.dart';
import 'config/release_check_extensions.dart';
import 'subscription_library.dart';
import 'ua_overrides.dart';

late DatabaseProvider gDatabaseProvider;
late SourceManager gSourceManager;
late RecentPlaysService gRecentPlaysService;
late Player gPlayer;
late DownloadManager gDownloadManager;

/// 发版前集成检查用：暂存最近一次人机验证挑战（key 与曲目 id）
String? debugCaptchaKey;
String? debugCaptchaId;

/// 播放缓存（离线可用）：与「已下载」分开存放，不写 localPath
late AudioCache gAudioCache;

Future<void> main() async {
  // 调试层：debug 用 FlanBinding（agent 驱动：元素枚举/手势/截图/日志/热重载/圈选回传），
  // release 保持默认 binding。必须是 kDebugMode 这种**编译期常量分支**，
  // 否则 kReleaseMode 下不会被树摇剔除（skill 4.4）。
  if (kDebugMode) {
    FlanBinding.ensureInitialized(agentDebugConfiguration());
    // Flan 的日志采集只监听 package:logging 的 root logger（skill 第 6 章）
    Logger.root.level = Level.ALL;
    _agentLogger = Logger('fm');
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

  // 网络图片缓存策略（磁盘缓存；集中配置，不在调用点硬编码天数）
  configureUiV2ImageCache();

  // 全局替换 dart:io 默认 User-Agent 为浏览器 UA
  // （网易等 CDN 对 Dart UA 做访问控制返回 403，见 ua_overrides_io.dart）
  applyBrowserUserAgent();

  // 1. 初始化 SQLite 数据库
  gDatabaseProvider = SqfliteDatabaseProvider();
  await gDatabaseProvider.initialize();

  // 源执行日志同时打印到控制台（便于排查插件失败）
  // print 直接输出：普通日志自带换行符时为多行（如 error 栈），保持可读；
  // 用 print 而非 debugPrint 避免 debugWordWrap 逐词断行。
  SourceLogBus.consolePrinter = (line) {
    print(line);
    // 单点桥接：这是项目日志唯一的扇出点，Flan 的 get_logs 从这里读
    if (kDebugMode) _bridgeLogToAgent(line);
  };

  // 2. 创建播放器、最近播放服务和下载管理器
  // 播放器自己也会补地址：队列曲目来自快照时没有 playUrl，
  // 上一首/下一首只能靠这个 resolver 现取
  gPlayer = PlayerImpl(
    // 播放器解析播放地址，统一走 UI 层解析器：已下载 → 播放缓存（离线）→ 源。
    // 前两者完全不请求源，所以"下一首/上一首/跳转"在断网或源失效时也能播；
    // 回源那一趟顺带把元数据登记落库（详情不会重复请求）。
    urlResolver: (song) async {
      final container = gContainer;
      if (container == null) return '';
      final res = await container.read(playSourceResolverProvider)(song);
      // 源站要求人机验证时这里没有地址：验证由 UI 层的验证面板接管
      // （这一路拿不到验证码；空地址会被播放器安全跳过，不会崩）
      return res.url;
    },
  );
  gRecentPlaysService =
      RecentPlaysService(gDatabaseProvider.recentPlaysDao);
  gDownloadManager = DownloadManagerImpl(songDao: gDatabaseProvider.songDao);
  gAudioCache = AudioCacheImpl();
  await gAudioCache.init();

  // 3. 创建 SourceManager 并注册源
  gSourceManager = SourceManager();
  gSourceManager.registerSource(LocalScanSource(gDatabaseProvider.songDao,
      gDatabaseProvider.settingsDao, const AudiotagsMetadataReader()));
  gSourceManager.registerSource(
      LocalCustomSource(gDatabaseProvider.songDao));
  gSourceManager.registerSource(
      FavoriteSource(gDatabaseProvider.favoritesDao, gSourceManager));
  // 演示曲库：把原型的内置配表包装成**真实音乐源**注册进 SourceManager，
  // 与本地源/规则源/插件源同构，可在「音乐源」页启用或停用。
  //
  // 配表本身没有音频，启动时生成一段静音 wav 注入，让演示曲库也能走通
  // 「取地址 → 播放 → 播放页/歌词/队列」整条链路；生成失败退回空串（旧行为）。
  final demoAudioUri = await _prepareDemoAudio();
  gSourceManager.registerSource(CatalogMusicSource(audioUri: demoAudioUri));

  // 4. 从 assets/rules/ 加载规则源
  await _loadRuleSources();

  // 4.1 从 assets/plugins/ 加载随包插件（历史上 v1 遗漏了这一步）
  await _loadBundledPlugins();

  // 4.2 初始化所有源：LocalScanSource 必须 init 才会把已扫描的曲目读进内存缓存，
  // 否则它的 search() 恒返回空（v1 的 main.dart 一直缺这一步）。
  await gSourceManager.initAll();

  // 4.3 订阅库：订阅页的宿主实现（远程规则 JSON → 音乐源）
  final subscriptions = SubscriptionLibrary(
    settingsDao: gDatabaseProvider.settingsDao,
    sourceManager: gSourceManager,
  );
  await subscriptions.load();
  gSubscriptions = subscriptions;

  // 5. 启动应用：手动建 ProviderContainer，便于 driver 钩子直接操作状态
  gContainer = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWith((ref) => gDatabaseProvider),
    sourceManagerProvider.overrideWith((ref) => gSourceManager),
    recentPlaysServiceProvider.overrideWith((ref) => gRecentPlaysService),
    playerProvider.overrideWith((ref) => gPlayer),
    downloadManagerProvider.overrideWith((ref) => gDownloadManager),
    audioCacheProvider.overrideWith((ref) => gAudioCache),
    subscriptionHostProvider.overrideWith((ref) => gSubscriptions!.host),
  ]);

  // 播放缓存：建立索引并把变更流接到版本号上（UI 的「离线可播」标记据此刷新）
  gContainer!.read(audioCacheBindingProvider);

  // 发版前集成检查的 debug-only 扩展（release 不含）
  if (kDebugMode) {
    registerReleaseCheckExtensions(runCommand: _driverCommand);
  }

  runApp(UncontrolledProviderScope(
    container: gContainer!,
    child: const FmApp(),
  ));
}

/// agent 日志桥：把项目日志转发给 Flan 采集（仅 debug 赋值）
Logger? _agentLogger;

/// 把一行项目日志转发到 package:logging，并按级别映射
///
/// 项目日志格式：[时间] [源id] LEVEL [动作] 详情
void _bridgeLogToAgent(String line) {
  final logger = _agentLogger;
  if (logger == null) return;
  // 项目日志行形如：[12:00:00] [源id] WARN [动作] 详情
  // 不用正则：这里只做级别归类，contains 足够且不会被转义坑到。
  final upper = line.toUpperCase();
  final Level level;
  if (upper.contains(' SEVERE ') || upper.contains(' ERROR ')) {
    level = Level.SEVERE;
  } else if (upper.contains(' WARNING ') || upper.contains(' WARN ')) {
    level = Level.WARNING;
  } else if (upper.contains(' FINE ') || upper.contains(' DEBUG ')) {
    level = Level.FINE;
  } else {
    level = Level.INFO;
  }
  logger.log(level, line);
}

/// 全局 ProviderContainer（driver 钩子与调试用；生产同进程也会建，但无外部入口）
ProviderContainer? gContainer;

/// 订阅库（订阅页宿主；启动时装配，driver/调试可读）
SubscriptionLibrary? gSubscriptions;

/// Flutter Driver 命令处理器 —— 只服务于 UI 自动化（截图 / 巡检）。
///
/// 支持的命令（[cmd] 为命令名，[p] 为参数表）：
///   * `navigate`：p['route'] 路由名、p['param'] 参数 → 切页面
///   * `back`：返回上一页
///   * `theme`：p['mode'] = dark/light/system
///   * `nowPlaying`：p['open'] = 1/0 展开或收起沉浸播放页
///   * `lyrics`：p['open'] = 1/0 切歌词视图
///   * `currentSong`：p['id'] 曲目 id（演示曲库 id 或全局键），并设置时长/进度；
///     只用于让播放页/歌词有内容可截，不写入最近播放
///   * `position`：p['ratio'] 进度比例（0~1）
///
/// 返回 null 表示命令已处理（Flutter Driver 约定）。
Future<String?> _driverCommand(String cmd, Map<String, String> p) async {
  final container = gContainer;
  if (container == null) return 'container not ready';
  switch (cmd) {
    case 'navigate':
      container
          .read(navProvider.notifier)
          .go(p['route'] ?? 'home', p['param'] ?? '');
    case 'back':
      container.read(navProvider.notifier).back();
    case 'dismiss':
      // 关掉所有模态浮层（recover 用：上一条用例留下的 sheet 会挡住后续点按与元素枚举）
      uiV2DismissOverlays();
    case 'theme':
      final mode = p['mode'] ?? 'dark';
      await container.read(themeModeProvider.notifier).setMode(switch (mode) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      });
    case 'nowPlaying':
      final open = p['open'] != '0';
      if (open) {
        container.read(nowPlayingProvider.notifier).open();
      } else {
        container.read(nowPlayingProvider.notifier).close();
      }
    case 'lyrics':
      // LyricsOpenNotifier 只有 toggle：先读当前值，与目标不一致才切
      final wantLyrics = p['open'] != '0';
      if (container.read(lyricsOpenProvider) != wantLyrics) {
        await container.read(lyricsOpenProvider.notifier).toggle();
      }
    case 'currentSong':
      final id = p['id'] ?? '';
      if (id.isEmpty) return 'missing id';
      final song = container.read(songResolverProvider)(id);
      if (song == null) return 'song not found: $id';
      container.read(currentTrackIdProvider.notifier).set(song.globalKey);
      final seconds = song.duration ?? 210;
      container
          .read(durationProvider.notifier)
          .set(Duration(seconds: seconds));
      container
          .read(positionProvider.notifier)
          .set(Duration(seconds: (seconds * 0.35).round()));
    case 'position':
      final ratio = double.tryParse(p['ratio'] ?? '') ?? 0.35;
      final total = container.read(durationProvider);
      container
          .read(positionProvider.notifier)
          .set(total * ratio.clamp(0.0, 1.0));
    case 'search':
      // 发版前集成检查用：直接触发一次聚合搜索（与 UI 输入走同一条 notifier 路径）
      //
      // wait=0 表示不等待搜索结束 —— 逐源渐进是时序行为，命令若 await 就会在
      // 采样前把整个过程跑完（实测 4 个源 250ms 内就出全了，根本看不到 loading）。
      final searchFut = container
          .read(searchProvider.notifier)
          .search(p['keyword'] ?? '', recordHistory: false);
      if (p['wait'] != '0') await searchFut;
    case 'songinfo':
      // 发版前集成检查用：把"界面认为的当前曲目"与"播放器真正在播的曲目"对照打出来
      final cur = container.read(currentSongProvider);
      final player = container.read(playerProvider);
      Song? audible;
      if (player is AudibleSongSource) {
        audible = (player as AudibleSongSource).audibleSong;
      }
      print('SONGINFO cur=${cur?.globalKey} title="${cur?.title}" artist="${cur?.artist}" '
          'playUrl="${cur?.playUrl}" dur=${cur?.duration} local="${cur?.localPath}"');
      print('SONGINFO audible=${audible?.globalKey} title="${audible?.title}" '
          'index=${player.currentIndex} queueLen=${player.queue.length}');
      return 'ok';
    case 'captchaui':
      // 发版前集成检查用：用真实验证图把"验证面板"走起来
      // （不依赖源站此刻是否要验证；提交后仍会真的按规则回传验证码）
      final fid = p['id'] ?? '61636';
      final imgFile = File('G:/works/shelli/fm/.dsh/tmp/captcha.bin');
      if (!await imgFile.exists()) return 'missing .dsh/tmp/captcha.bin';
      final b64 = base64Encode(await imgFile.readAsBytes());
      const demoSong =
          Song(id: '61636', sourceId: 'gequbao', title: '默', artist: '那英');
      container.read(pendingCaptchaProvider.notifier).set(PendingCaptcha(
            demoSong,
            PlaybackChallenge(
              image: 'data:image/jpeg;base64,' + b64,
              key: 'debug-key',
              codeField: 'captchaCode',
              keyField: 'key',
              message: '真机演练：请输入图中验证码',
            ),
          ));
      print('CAPTCHAUI 已挂起验证面板 id=' + fid + ' 图字节=' + b64.length.toString());
      return 'ok';
    case 'captchaimg':
      // 发版前集成检查用：取验证图并写成 PNG，供人工看图输入验证码
      final cid = p['id'] ?? '';
      if (cid.isEmpty) return 'missing id';
      final info = await gSourceManager.getPlayable('gequbao', cid);
      if (!info.needsChallenge) {
        print('CAPTCHA 无需验证 url=' + info.url);
        return 'ok';
      }
      debugCaptchaKey = info.challenge!.key;
      debugCaptchaId = cid;
      print('CAPTCHA key=' +
          info.challenge!.key +
          ' msg=' +
          info.challenge!.message +
          ' imgLen=' +
          info.challenge!.image.length.toString());
      final raw = info.challenge!.image;
      final b64 = raw.contains(',') ? raw.split(',').last : raw;
      final out = File('G:/works/shelli/fm/.dsh/tmp/captcha.png');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(base64Decode(b64));
      print('CAPTCHA 验证图已写入 ' + out.path);
      return 'ok';
    case 'captchaplay':
      // 发版前集成检查用：带验证码重试换取播放地址，并真的提交播放
      final code = p['code'] ?? '';
      final cid2 = debugCaptchaId;
      if (code.isEmpty || cid2 == null) return 'missing code（先 captchaimg）';
      final info2 = await gSourceManager.getPlayable('gequbao', cid2,
          captchaCode: code, captchaKey: debugCaptchaKey);
      print('CAPTCHA 重试 needsChallenge=' +
          info2.needsChallenge.toString() +
          ' url=' +
          info2.url);
      if (info2.url.isNotEmpty) {
        final meta = info2.meta ??
            Song(id: cid2, sourceId: 'gequbao', title: '', artist: '');
        await container
            .read(playerProvider)
            .play(meta.copyWith(playUrl: info2.url));
        print('CAPTCHA 已提交播放');
      }
      return 'ok';
    case 'captchainfo':
      // 发版前集成检查用：验证一次之后，其它受控曲目是否免验证
      final sid = p['id'] ?? '';
      if (sid.isEmpty) return 'missing id';
      final info3 = await gSourceManager.getPlayable('gequbao', sid);
      print('CAPTCHA 查询 id=' +
          sid +
          ' needsChallenge=' +
          info3.needsChallenge.toString() +
          ' url=' +
          info3.url);
      return 'ok';
    case 'dbsong':
      // 发版前集成检查用：按 id + source 查库里的曲目行（诊断"库里到底是什么"）
      final did = p['id'] ?? '';
      final dsrc = p['source'] ?? '';
      if (did.isEmpty || dsrc.isEmpty) return 'missing id/source';
      final drow =
          await container.read(songDaoProvider).getSong(did, dsrc);
      print('DBSONG key=$dsrc:$did title="${drow?.title}" artist="${drow?.artist}" '
          'album="${drow?.album}" cover="${drow?.coverUrl}" dur=${drow?.duration} '
          'lyricLen=${(drow?.lyric ?? '').length} local="${drow?.localPath}"');
      return 'ok';
    case 'sourceEnabled':
      // 发版前集成检查用：停用/启用某个源（模拟"源失效"），状态会持久化
      final sid = p['id'] ?? '';
      if (sid.isEmpty) return 'missing id';
      // 收敛后唯一入口是 SourceEnabledActions（改 manager + 落库 + 通知 UI）
      await container
          .read(sourceEnabledActionsProvider)
          .set(sid, p['on'] == '1');
      return 'source $sid enabled=${p['on'] == '1'}';
    case 'dbinfo':
      // 发版前集成检查用：把"当前曲目在 UI 侧的快照"与"DB 里存的行"并排回读，
      // 用于判断"显示不到封面"到底是源没给、还是缓存没写、还是展示层没读。
      final cur = container.read(currentSongProvider);
      if (cur == null) return jsonEncode({'error': 'no current song'});
      final row = await gDatabaseProvider.songDao.getSong(cur.id, cur.sourceId);
      // 同时打进 App 日志，便于驱动跑完后直接取证
      print('DBINFO ' +
          jsonEncode({
            'key': cur.globalKey,
            'snapCover': cur.coverUrl,
            'snapDur': cur.duration,
            'dbCover': row?.coverUrl,
            'dbDur': row?.duration,
            'dbLocal': row?.localPath,
          }));
      return jsonEncode({
        'key': cur.globalKey,
        'snapshot': {
          'title': cur.title,
          'cover': cur.coverUrl,
          'duration': cur.duration,
        },
        'db': row == null
            ? null
            : {
                'title': row.title,
                'cover': row.coverUrl,
                'duration': row.duration,
                'localPath': row.localPath,
                'lyricLen': (row.lyric ?? '').length,
              },
      });
    case 'playplaylist': {
      // 发版前集成检查用：把某个歌单当作队列播起来（走 UI 同一条 playInQueue 路径）
      final pls = await container.read(playlistsProvider.future);
      if (pls.isEmpty) return 'no playlist';
      final wanted = p['id'];
      Playlist pl = pls.first;
      if (wanted != null && wanted.isNotEmpty) {
        for (final e in pls) {
          if (e.id == wanted || e.name == wanted) {
            pl = e;
            break;
          }
        }
      }
      final songs = await container.read(playlistSongsProvider(pl.id).future);
      if (songs.isEmpty) return 'empty playlist ' + pl.name;
      final start = int.tryParse(p['index'] ?? '') ?? 0;
      final started = await container
          .read(playbackControllerProvider)
          .playInQueue(
            PlayQueue(
              kind: PlayQueueKind.playlist,
              id: pl.id,
              title: pl.name,
              songs: songs,
            ),
            startIndex: start,
          );
      print('PLAYPLAYLIST id=' + pl.id + ' name=' + pl.name +
          ' songs=' + songs.length.toString() + ' started=' + started.toString());
      return started ? 'ok' : 'not started';
    }
    case 'playrecent': {
      // 发版前集成检查用：切到"最近播放"队列（用于验证"切队列时先把旧队列进度存下来"）
      final songs = container.read(recentSongsProvider);
      if (songs.isEmpty) return 'recent empty';
      final started = await container.read(playbackControllerProvider).playInQueue(
            PlayQueue(
              kind: PlayQueueKind.recent,
              title: '最近播放',
              songs: songs,
            ),
          );
      print('PLAYRECENT songs=' + songs.length.toString() +
          ' started=' + started.toString());
      return started ? 'ok' : 'not started';
    }
    case 'restorenow':
      // 发版前集成检查用：手动重跑一次"启动恢复"（invalidte 会让它对同一 Ref 重跑，
      // 这样不用重启 App 也能看到它每一步走到哪、失败在哪）
      container.invalidate(startupResumeProvider);
      await container.read(startupResumeProvider.future);
      print('RESTORENOW done');
      return 'ok';
    case 'resumeplaylist': {
      // 发版前集成检查用：走"歌单卡片的播放键"同一条路径（TrackActions.resume → resumeInQueue）
      final pls = await container.read(playlistsProvider.future);
      if (pls.isEmpty) return 'no playlist';
      final wanted = p['id'];
      Playlist pl = pls.first;
      if (wanted != null && wanted.isNotEmpty) {
        for (final e in pls) {
          if (e.id == wanted || e.name == wanted) {
            pl = e;
            break;
          }
        }
      }
      final songs = await container.read(playlistSongsProvider(pl.id).future);
      if (songs.isEmpty) return 'empty playlist ' + pl.name;
      final saved = await container
          .read(playbackControllerProvider)
          .savedProgress(PlayQueue(
            kind: PlayQueueKind.playlist,
            id: pl.id,
            title: pl.name,
            songs: songs,
          ));
      final started = await container
          .read(playbackControllerProvider)
          .resumeInQueue(PlayQueue(
            kind: PlayQueueKind.playlist,
            id: pl.id,
            title: pl.name,
            songs: songs,
          ));
      print('RESUMEPLAYLIST name=' + pl.name +
          ' savedSong=' + (saved?.songKey ?? 'none') +
          ' savedMs=' + (saved?.positionMs ?? 0).toString() +
          ' started=' + started.toString());
      return started ? 'ok' : 'not started';
    }
    case 'npopen':
      // 发版前集成检查用：打开沉浸播放页（不依赖点击播放条上的展开键）
      container.read(nowPlayingProvider.notifier).open();
      print('NPOPEN opened=' + container.read(nowPlayingProvider).toString());
      return 'ok';
    case 'npclose':
      container.read(nowPlayingProvider.notifier).close();
      return 'ok';
    case 'recentrows': {
      // 发版前集成检查用：最近播放前几条的"行内 key / 是否缓存 / localPath"对照
      final cache = container.read(audioCacheProvider);
      final songs = container.read(recentSongsProvider);
      for (var i = 0; i < songs.length && i < 6; i++) {
        final s = songs[i];
        print('RECENTROW ' + i.toString() +
            ' key=' + s.globalKey +
            ' id=' + s.id +
            ' sourceId=' + s.sourceId +
            ' cached=' + cache.isCached(s.globalKey).toString() +
            ' localPath=' + (s.localPath ?? 'null') +
            ' title=' + s.title);
      }
      return 'ok';
    }
    case 'cachecheck': {
      // 发版前集成检查用：核对"界面说没缓存"到底是索引没建好，还是文件不在
      final cache = container.read(audioCacheProvider);
      final keys = cache.cachedKeys.toList()..sort();
      final key = p['key'] ?? '6uq:eWZ2a2V2a2tq';
      print('CACHECHECK key=' + key +
          ' isCached=' + cache.isCached(key).toString() +
          ' total=' + keys.length.toString() +
          ' localUrl=' + (cache.localUrlFor(key) ?? 'null'));
      print('CACHECHECK keys=' + keys.join(','));
      return cache.isCached(key) ? 'cached' : 'missing';
    }
    case 'progress': {
      // 发版前集成检查用：把 play_progress 表与当前队列/进度并排回读，
      // 判断"能不能从上次继续"到底是没写、没读到、还是没恢复。
      final rows = await gDatabaseProvider.playProgressDao.getAll();
      final queue = container.read(queueProvider);
      final pos = container.read(positionProvider).inMilliseconds;
      final playing = container.read(isPlayingProvider);
      final cur = container.read(currentTrackIdProvider);
      print('PROGRESS ' +
          jsonEncode({
            'rows': [
              for (final r in rows)
                {
                  'identity': r.identity,
                  'songKey': r.songKey,
                  'posMs': r.positionMs,
                  'updatedAt': r.updatedAt,
                },
            ],
            'queueKind': queue.kind.name,
            'queueTitle': queue.title,
            'queueLen': queue.length,
            'current': cur,
            'posMs': pos,
            'playing': playing,
          }));
      return jsonEncode({'rows': rows.length, 'queue': queue.title, 'posMs': pos});
    }
    case 'setmode':
      // 发版前集成检查用：直接设播放模式（list/single/shuffle/sequential）
      await container.read(playModeProvider.notifier).set(switch (p['mode']) {
        'single' => PlayMode.singleLoop,
        'shuffle' => PlayMode.shuffle,
        'sequential' => PlayMode.sequential,
        _ => PlayMode.listLoop,
      });
      print('CMDSETMODE mode=' + container.read(playModeProvider).name);
    case 'seekend':
      // 发版前集成检查用：跳到结尾前 [p.leadMs]（默认 2000）毫秒，
      // 让「播完自动切下一首」能在几秒内被观察到，而不是真等一首歌。
      final player = container.read(playerProvider);
      final dur = player.currentDuration;
      if (dur <= 0) return 'no-duration';
      final lead = int.tryParse(p['leadMs'] ?? '2000') ?? 2000;
      final target = dur - lead;
      await player.seek(Duration(milliseconds: target < 0 ? 0 : target));
      print('CMDSEEKEND target=' + target.toString() + ' dur=' + dur.toString());
    case 'searchstate':
      // 发版前集成检查用：把逐源加载状态打进日志 —— 「逐源渐进」是时序行为，
      // 截图看不清，用这个命令在几个时刻取样才能断言。
      final st = container.read(searchProvider);
      print('CMDSEARCH kw=' +
          st.keyword +
          ' loading=' +
          st.loading.toString() +
          ' pools=[' +
          st.pools
              .map((p) =>
                  p.name + ':' + (p.loading ? 'loading' : p.songs.length.toString()))
              .join(', ') +
          ']');
    case 'playnow':
      // 发版前集成检查用：把当前在播曲目/模式/进度打进日志，
      // 便于断言「播完是否自动换歌」（停在同一首 = 单曲循环）
      print('CMDNOW song=' +
          '${container.read(currentTrackIdProvider)}' +
          ' mode=' +
          container.read(playModeProvider).name +
          ' pos=' +
          container.read(positionProvider).inMilliseconds.toString() +
          ' dur=' +
          container.read(durationProvider).inMilliseconds.toString() +
          ' shuffle=' +
          container.read(shuffleProvider).toString() +
          ' queue=' +
          container.read(queueProvider).length.toString());
    case 'state':
      // 发版前集成检查用：把当前导航/曲目/主题等状态回读给驱动，
      // 让"点了之后到底变没变"可以被断言，而不是只看截图猜。
      // 仅在 FM_DRIVER=true 时存在（整个 handler 包在 kEnableFlutterDriver 分支里）。
      final nav = container.read(navProvider);
      return jsonEncode({
        'route': nav.current.name,
        'param': nav.current.param,
        'song': '${container.read(currentTrackIdProvider)}',
        'theme': container.read(themeModeProvider).name,
        'posMs': container.read(positionProvider).inMilliseconds,
        'durMs': container.read(durationProvider).inMilliseconds,
        'lyrics': container.read(lyricsOpenProvider),
        'queue': container.read(queueProvider).length,
        'playMode': container.read(playModeProvider).name,
        'shuffle': container.read(shuffleProvider),
        'volume': '${container.read(volumeProvider)}',
        'liked': container.read(favoriteCountProvider),
      });
    default:
      return 'unknown command: $cmd';
  }
  // 让状态变更后的重建先落地，驱动侧再截图就不会截到旧帧
  await Future<void>.delayed(const Duration(milliseconds: 400));
  return null;
}

/// 从 assets/plugins/ 加载随包插件文件（.json 规则 / .js 插件）
///
/// 与 assets/rules/ 的区别只在来源目录；两者都注册进同一个 SourceManager。
Future<void> _loadBundledPlugins() async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final files = manifest
        .listAssets()
        .where((key) =>
            key.startsWith('assets/plugins/') &&
            (key.endsWith('.json') || key.endsWith('.js')))
        .toList();
    if (files.isEmpty) return;

    // 插件需要真实文件路径，先把资产落到应用支持目录
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'bundled_plugins'));
    await dir.create(recursive: true);
    for (final path in files) {
      final name = p.basename(path);
      final target = File(p.join(dir.path, name));
      if (!await target.exists()) {
        final data = await rootBundle.load(path);
        await target.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
    }
    final sources = await PluginManager.loadPluginsFromDirectory(dir.path);
    for (final source in sources) {
      gSourceManager.registerSource(source);
    }
    debugPrint('随包插件加载完成：${sources.length} 个');
  } catch (e) {
    debugPrint('加载随包插件失败: $e');
  }
}

/// 从 assets/rules/ 加载所有 .json 规则文件
///
/// 注意：Flutter ≥3.16 不再生成 AssetManifest.json（改为二进制格式），
/// 必须用官方 AssetManifest API 发现资产，否则一条规则都加载不到。
Future<void> _loadRuleSources() async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final ruleFiles = manifest
        .listAssets()
        .where((key) =>
            key.startsWith('assets/rules/') && key.endsWith('.json'))
        .toList();

    for (final path in ruleFiles) {
      try {
        final jsonStr = await rootBundle.loadString(path);
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        final config = RuleConfig.fromJson(json);
        final source = RuleBasedMusicSource(config);
        gSourceManager.registerSource(source);
        gSourceManager.setSourceEnabled(config.source.id, true);
      } catch (e) {
        debugPrint('加载规则源失败: $path — $e');
      }
    }
  } catch (e) {
    debugPrint('加载规则源目录失败: $e');
  }
}

/// 生成（一次）一段静音 wav 并返回 file:// URI，供演示曲库当占位音频。
///
/// 用代码生成而不是塞二进制资产：不增仓库体积、无版权问题，只写应用支持目录。
Future<String> _prepareDemoAudio() async {
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'demo_placeholder.wav'));
    if (!await file.exists()) {
      await file.writeAsBytes(_silentWav(), flush: true);
    }
    return file.uri.toString();
  } catch (e) {
    debugPrint('生成演示占位音频失败: $e');
    return '';
  }
}

/// 8kHz / 单声道 / 16bit 的 RIFF-WAVE 静音 PCM（默认 10 秒）
List<int> _silentWav({int seconds = 10, int sampleRate = 8000}) {
  final dataLen = sampleRate * seconds * 2;
  final out = BytesBuilder();
  void tag(String s) => out.add(ascii.encode(s));
  void u32(int v) =>
      out.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  void u16(int v) => out.add([v & 0xFF, (v >> 8) & 0xFF]);
  tag('RIFF');
  u32(36 + dataLen);
  tag('WAVE');
  tag('fmt ');
  u32(16);
  u16(1); // PCM
  u16(1); // 单声道
  u32(sampleRate);
  u32(sampleRate * 2); // byte rate
  u16(2); // block align
  u16(16); // bits per sample
  tag('data');
  u32(dataLen);
  out.add(Uint8List(dataLen));
  return out.takeBytes();
}

/// 应用根 Widget（uiv2 版本）
///
/// 主题与令牌作用域由 uiv2 的 [UiV2App] 负责：uiv2 使用原型自带的配色令牌
/// （深色为默认），不再叠加 v1 的种子色 / 圆角设置，避免两套视觉系统互相覆盖。
class FmApp extends ConsumerWidget {
  /// 构造应用根
  const FmApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const UiV2App();
  }
}
