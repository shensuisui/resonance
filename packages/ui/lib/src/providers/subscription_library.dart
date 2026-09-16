/// 远程源订阅库 —— 规则/插件的订阅、展开、更新与来源追踪
///
/// 一切远程添加都是「订阅」，订阅按类型展开出 N 个源：
/// - singleRule   单个规则 JSON（含 source 字段）        → 1 个规则源
/// - ruleGroup    规则数组 或 {"rules":[...]}            → N 个规则源
/// - mfGroup      MusicFree 插件索引 [{"name","url"}]    → N 个插件源
/// - singlePlugin 单个插件文件（.js/.lx 内容）           → 1 个插件源
///
/// 存储（按订阅目录隔离，目录即来源归属）：
/// ```
/// 支持目录/subscriptions/
///   index.json              # 订阅列表
///   <urlHash>/manifest.json # 展开清单（sourceId ↔ 文件名）
///   <urlHash>/<files>       # 展开的规则/插件文件
/// ```
///
/// 更新语义：重新拉取 → 展开 → 与 manifest 差异比对，
/// 新增/变更写盘注册，消失项删文件并注销。
/// 条目失败跳过继续，最终报告成功/失败数。

import 'dart:convert';
import 'dart:io';

import 'package:crawler/crawler.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';

import 'providers.dart';

part 'subscription_library.g.dart';

/// 订阅类型（导入时手动指定）
enum SubscriptionType {
  /// 单个规则
  singleRule,

  /// 规则订阅组
  ruleGroup,

  /// MusicFree 插件订阅组
  mfGroup,

  /// 单个插件文件
  singlePlugin,
}

extension SubscriptionTypeLabel on SubscriptionType {
  String get label => switch (this) {
        SubscriptionType.singleRule => '规则',
        SubscriptionType.ruleGroup => '规则订阅组',
        SubscriptionType.mfGroup => 'MusicFree 订阅组',
        SubscriptionType.singlePlugin => '单插件',
      };

  String toJson() => name;

  static SubscriptionType fromJson(String value) => SubscriptionType.values
      .firstWhere((t) => t.name == value, orElse: () => SubscriptionType.singleRule);
}

/// 订阅条目
class Subscription {
  final String url;
  final SubscriptionType type;

  /// 别名（可选，用户命名，便于识别）
  final String? name;
  final DateTime addedAt;
  final DateTime? lastCheckedAt;

  const Subscription({
    required this.url,
    required this.type,
    required this.addedAt,
    this.name,
    this.lastCheckedAt,
  });

  Subscription copyWith({DateTime? lastCheckedAt}) => Subscription(
        url: url,
        type: type,
        name: name,
        addedAt: addedAt,
        lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'type': type.toJson(),
        if (name != null) 'name': name,
        'addedAt': addedAt.millisecondsSinceEpoch,
        if (lastCheckedAt != null)
          'lastCheckedAt': lastCheckedAt!.millisecondsSinceEpoch,
      };

  static Subscription fromJson(Map<String, dynamic> json) => Subscription(
        url: json['url'] as String,
        type: SubscriptionTypeLabel.fromJson(json['type'] as String),
        name: json['name'] as String?,
        addedAt:
            DateTime.fromMillisecondsSinceEpoch(json['addedAt'] as int),
        lastCheckedAt: json['lastCheckedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                json['lastCheckedAt'] as int),
      );
}

/// 订阅库状态
class SubscriptionState {
  /// 已登记的订阅
  final List<Subscription> subscriptions;

  /// 来源归属：sourceId → 订阅 url
  final Map<String, String> sourceOrigin;

  /// 每个订阅展开的源数量：url → count
  final Map<String, int> sourceCounts;

  final bool loading;
  final String? message;

  const SubscriptionState({
    this.subscriptions = const [],
    this.sourceOrigin = const {},
    this.sourceCounts = const {},
    this.loading = false,
    this.message,
  });
}

/// 展开结果：一个订阅拉取后产出的全部源
class _ExpandedItem {
  final String sourceId;
  final String fileName;
  final String content;
  final MusicSource source;

  const _ExpandedItem(this.sourceId, this.fileName, this.content, this.source);
}

@Riverpod(keepAlive: true)
class SubscriptionLibrary extends _$SubscriptionLibrary {
  @override
  SubscriptionState build() {
    loadLocal();
    return const SubscriptionState(loading: true);
  }

  SourceManager get _sourceManager => ref.read(sourceManagerProvider);

  // ==================== 目录与索引 ====================

  Future<String> get _rootDir async {
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'subscriptions');
  }

  /// url → 稳定的目录名（base64url，跨重启稳定）
  String _dirNameOf(String url) => base64Url.encode(utf8.encode(url));

  Future<String> _subDirOf(String url) async =>
      p.join(await _rootDir, _dirNameOf(url));

  /// 读订阅索引；不存在返回空表
  Future<List<Subscription>> _readIndex() async {
    try {
      final file = File(p.join(await _rootDir, 'index.json'));
      if (!await file.exists()) return [];
      final list = jsonDecode(await file.readAsString()) as List<dynamic>;
      return list
          .map((e) => Subscription.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeIndex(List<Subscription> subs) async {
    final root = await _rootDir;
    await Directory(root).create(recursive: true);
    final file = File(p.join(root, 'index.json'));
    await file.writeAsString(jsonEncode(subs.map((s) => s.toJson()).toList()));
  }

  /// 读某订阅的展开清单：sourceId → 文件名
  Future<Map<String, String>> _readManifest(String url) async {
    try {
      final file = File(p.join(await _subDirOf(url), 'manifest.json'));
      if (!await file.exists()) return {};
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return map.cast<String, String>();
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeManifest(String url, Map<String, String> manifest) async {
    final dir = Directory(await _subDirOf(url));
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'manifest.json'))
        .writeAsString(jsonEncode(manifest));
  }

  // ==================== 对外操作 ====================

  /// 启动加载：仅从本地文件恢复注册，不访问网络
  Future<void> loadLocal() async {
    try {
      final subs = await _readIndex();
      final origin = <String, String>{};
      final counts = <String, int>{};
      for (final sub in subs) {
        final n = await _registerFromDisk(sub);
        counts[sub.url] = n;
      }
      // 来源映射从各订阅清单重建
      for (final sub in subs) {
        final manifest = await _readManifest(sub.url);
        for (final id in manifest.keys) {
          origin[id] = sub.url;
        }
      }
      state = SubscriptionState(
        subscriptions: subs,
        sourceOrigin: origin,
        sourceCounts: counts,
      );
    } catch (e) {
      state = SubscriptionState(message: '订阅本地加载失败: $e');
    }
  }

  /// 添加订阅：拉取 → 展开 → 落盘 → 注册
  ///
  /// [name] 为可选的订阅别名，便于识别。
  Future<bool> addSubscription(String url, SubscriptionType type,
      {String? name}) async {
    final subs = await _readIndex();
    if (subs.any((s) => s.url == url)) {
      state = _withMessage('该地址已存在');
      return false;
    }
    final sub = Subscription(
        url: url,
        type: type,
        name: (name == null || name.trim().isEmpty) ? null : name.trim(),
        addedAt: DateTime.now());
    final ok = await _fetchAndSync(sub, isFirstAdd: true);
    if (!ok) return false;
    final updated = await _readIndex();
    state = SubscriptionState(
      subscriptions: updated,
      sourceOrigin: state.sourceOrigin,
      sourceCounts: {...state.sourceCounts, url: await _countOf(url)},
      message: '订阅添加成功',
    );
    return true;
  }

  /// 检查更新单个订阅
  Future<void> updateSubscription(String url) async {
    final subs = await _readIndex();
    final sub = subs.where((s) => s.url == url).firstOrNull;
    if (sub == null) return;
    final ok = await _fetchAndSync(sub);
    if (ok) {
      final updated = await _readIndex();
      state = SubscriptionState(
        subscriptions: updated,
        sourceOrigin: state.sourceOrigin,
        sourceCounts: {...state.sourceCounts, url: await _countOf(url)},
        message: '更新完成',
      );
    }
  }

  /// 检查更新全部订阅，返回 (成功数, 失败数)
  Future<(int, int)> updateAll() async {
    final subs = await _readIndex();
    var okCount = 0;
    var failCount = 0;
    for (final sub in subs) {
      if (await _fetchAndSync(sub)) {
        okCount++;
      } else {
        failCount++;
      }
    }
    final updated = await _readIndex();
    final counts = <String, int>{};
    for (final s in updated) {
      counts[s.url] = await _countOf(s.url);
    }
    state = SubscriptionState(
      subscriptions: updated,
      sourceOrigin: state.sourceOrigin,
      sourceCounts: counts,
      message: '全部更新完成：成功 $okCount，失败 $failCount',
    );
    return (okCount, failCount);
  }

  /// 删除订阅：注销其全部源、删目录、清索引
  Future<void> removeSubscription(String url) async {
    // 注销该订阅的全部源
    final manifest = await _readManifest(url);
    for (final id in manifest.keys) {
      _sourceManager.unregisterSource(id);
    }
    // 删目录
    final dir = Directory(await _subDirOf(url));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    // 清索引
    final subs = await _readIndex().then(
        (list) => list.where((s) => s.url != url).toList());
    await _writeIndex(subs);

    final origin = {...state.sourceOrigin};
    origin.removeWhere((id, u) => u == url);
    final counts = {...state.sourceCounts};
    counts.remove(url);
    state = SubscriptionState(
      subscriptions: subs,
      sourceOrigin: origin,
      sourceCounts: counts,
      message: '订阅已删除',
    );
  }

  /// 登记 PRD 默认订阅（落雪单插件 + MusicFree 订阅组）
  Future<int> addDefaultSubscriptions() async {
    var ok = 0;
    final defaults = [
      (
        '落雪音乐',
        'https://fastly.jsdelivr.net/gh/Huibq/keep-alive/render_api.js',
        SubscriptionType.singlePlugin
      ),
      (
        'MusicFree 官方源',
        'https://fastly.jsdelivr.net/gh/Huibq/keep-alive/Music_Free/myPlugins.json',
        SubscriptionType.mfGroup
      ),
    ];
    for (final (name, url, type) in defaults) {
      if (await addSubscription(url, type, name: name)) {
        ok++;
      }
    }
    return ok;
  }

  // ==================== 内部实现 ====================

  Future<int> _countOf(String url) async =>
      (await _readManifest(url)).length;

  /// 从磁盘恢复某订阅的全部源（启动用，无网络）
  Future<int> _registerFromDisk(Subscription sub) async {
    final manifest = await _readManifest(sub.url);
    final dir = Directory(await _subDirOf(sub.url));
    var count = 0;
    for (final entry in manifest.entries) {
      final file = File(p.join(dir.path, entry.value));
      if (!await file.exists()) continue;
      try {
        final source = await _convertFile(file, sub.type);
        if (source != null) {
          _sourceManager.registerSource(source);
          ref.invalidate(sourceListProvider);
          count++;
        } else {
          SourceLogBus.instance.emit(
            'subscription', SourceLogLevel.error, '订阅恢复',
            '文件转换失败 ${file.path}（type=${sub.type.name}）');
        }
      } catch (e) {
        SourceLogBus.instance.emit(
          'subscription', SourceLogLevel.error, '订阅恢复',
          '恢复源失败 ${file.path}: $e');
      }
    }
    return count;
  }

  /// 拉取订阅并同步（新增或更新共用）
  ///
  /// 返回是否成功。条目级失败跳过不阻断。
  Future<bool> _fetchAndSync(Subscription sub, {bool isFirstAdd = false}) async {
    try {
      // 1. 拉取订阅内容
      final client = HttpClient(timeout: const Duration(seconds: 30));
      HttpResponse resp;
      try {
        resp = await client.get(sub.url, responseType: 'text');
      } finally {
        client.dispose();
      }
      final raw = resp.rawData;

      // 2. 按类型展开为源列表
      final items = await _expand(sub, raw);

      // 3. 与旧 manifest 差异比对
      final oldManifest = await _readManifest(sub.url);
      final dir = Directory(await _subDirOf(sub.url));
      await dir.create(recursive: true);

      final newManifest = <String, String>{};
      for (final item in items) {
        newManifest[item.sourceId] = item.fileName;
        await File(p.join(dir.path, item.fileName))
            .writeAsString(item.content);
        _sourceManager.registerSource(item.source);
      }
      ref.invalidate(sourceListProvider);

      // 消失项：删文件 + 注销
      for (final id in oldManifest.keys) {
        if (!newManifest.containsKey(id)) {
          _sourceManager.unregisterSource(id);
          final oldFile = File(p.join(dir.path, oldManifest[id]!));
          if (await oldFile.exists()) await oldFile.delete();
        }
      }

      // 4. 写 manifest + 更新索引时间戳
      await _writeManifest(sub.url, newManifest);
      final subs = await _readIndex();
      final idx = subs.indexWhere((s) => s.url == sub.url);
      final checked = sub.copyWith(lastCheckedAt: DateTime.now());
      if (idx >= 0) {
        subs[idx] = checked;
      } else {
        subs.add(checked);
      }
      await _writeIndex(subs);

      // 刷新来源映射
      final origin = {...state.sourceOrigin};
      for (final id in newManifest.keys) {
        origin[id] = sub.url;
      }
      state = SubscriptionState(
        subscriptions: subs,
        sourceOrigin: origin,
        sourceCounts: state.sourceCounts,
      );
      return true;
    } catch (e) {
      state = _withMessage(isFirstAdd ? '订阅添加失败: $e' : '更新失败: $e');
      return false;
    }
  }

  /// 按订阅类型把原始内容展开为源列表
  Future<List<_ExpandedItem>> _expand(
      Subscription sub, String raw) async {
    switch (sub.type) {
      case SubscriptionType.singleRule:
        final item = await _expandRuleItem(raw, '.json');
        return item == null ? [] : [item];

      case SubscriptionType.ruleGroup:
        final decoded = jsonDecode(raw);
        final List<dynamic> elements;
        if (decoded is List) {
          elements = decoded;
        } else if (decoded is Map && decoded['rules'] is List) {
          elements = decoded['rules'] as List<dynamic>;
        } else {
          throw FormatException('规则订阅组格式不正确');
        }
        final items = <_ExpandedItem>[];
        for (final element in elements) {
          final item =
              await _expandRuleItem(jsonEncode(element), '.json');
          if (item != null) items.add(item);
        }
        return items;

      case SubscriptionType.mfGroup:
        final entries = parseMfGroupEntries(raw);
        final items = <_ExpandedItem>[];
        for (final entry in entries) {
          if (entry is! Map || entry['url'] is! String) continue;
          final entryUrl = entry['url'] as String;
          final ext = entryUrl.toLowerCase().endsWith('.json')
              ? '.json'
              : '.js';
          try {
            final client = HttpClient(timeout: const Duration(seconds: 30));
            HttpResponse resp;
            try {
              resp = await client.get(entryUrl, responseType: 'text');
            } finally {
              client.dispose();
            }
            final item = await _expandPluginItem(resp.rawData, ext);
            if (item != null) items.add(item);
          } catch (e) {
            // 单条目失败跳过，记录原因供排查
            SourceLogBus.instance.emit(
              sub.url,
              SourceLogLevel.error,
              '订阅展开',
              'MusicFree 插件条目 $entryUrl 展开失败: $e',
            );
          }
        }
        return items;

      case SubscriptionType.singlePlugin:
        final ext = sub.url.toLowerCase().endsWith('.json') ? '.json' : '.js';
        final item = await _expandPluginItem(raw, ext);
        return item == null ? [] : [item];
    }
  }

  /// 解析 MusicFree 插件订阅组内容
  ///
  /// 兼容两种实际存在的索引格式：
  /// 1. 裸 List：[{"name","url"}, ...]
  /// 2. 带 plugins 键：{"plugins":[...]}（官方 myPlugins.json 即此格式）
  ///
  /// 非法内容（JSON 解析失败 / 非 List / 无 plugins 键的 Map）抛 FormatException。
  static List<dynamic> parseMfGroupEntries(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is List) return decoded;
    if (decoded is Map && decoded['plugins'] is List) {
      return decoded['plugins'] as List<dynamic>;
    }
    throw const FormatException('MusicFree 订阅组格式不正确');
  }

  /// 展开单个规则内容
  Future<_ExpandedItem?> _expandRuleItem(String raw, String ext) async {
    final config = RuleLoader.loadFromJson(raw);
    if (config == null) {
      SourceLogBus.instance.emit(
        'subscription', SourceLogLevel.error, '规则展开',
        '规则 JSON 解析失败\n内容前 200 字符: '
        '${raw.length > 200 ? raw.substring(0, 200) : raw}');
      return null;
    }
    final source = RuleBasedMusicSource(config);
    final id = config.source.id;
    return _ExpandedItem(id, '$id$ext', raw, source);
  }

  /// 展开单个插件内容
  Future<_ExpandedItem?> _expandPluginItem(String raw, String ext) async {
    final MusicSource? source;
    if (ext == '.json') {
      source = MusicFreeAdapter.convertToSource(raw);
    } else {
      source = await LxMusicAdapter.tryCreate(raw);
    }
    if (source == null) {
      SourceLogBus.instance.emit(
        'subscription', SourceLogLevel.error, '插件展开',
        '插件内容创建源失败（ext=$ext）\n内容前 200 字符: '
        '${raw.length > 200 ? raw.substring(0, 200) : raw}');
      return null;
    }
    final id = source.sourceInfo.id;
    return _ExpandedItem(id, '$id$ext', raw, source);
  }

  /// 启动恢复时从文件转换源
  Future<MusicSource?> _convertFile(File file, SubscriptionType type) async {
    final content = await file.readAsString();
    final isJson = p.extension(file.path).toLowerCase() == '.json';
    if (type == SubscriptionType.singleRule ||
        type == SubscriptionType.ruleGroup) {
      final config = RuleLoader.loadFromJson(content);
      return config == null ? null : RuleBasedMusicSource(config);
    }
    return isJson
        ? MusicFreeAdapter.convertToSource(content)
        : LxMusicAdapter.tryCreate(content);
  }

  SubscriptionState _withMessage(String msg) => SubscriptionState(
        subscriptions: state.subscriptions,
        sourceOrigin: state.sourceOrigin,
        sourceCounts: state.sourceCounts,
        message: msg,
      );
}
