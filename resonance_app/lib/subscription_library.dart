/// 订阅库：把「远程规则 JSON 地址」展开成音乐源，并持久化到 settings 表。
///
/// 一条订阅 = 一个 http(s) 地址，内容是规则源 JSON（[RuleConfig]）。
/// 展开动作 = 拉取 JSON → 解析 → 构造 [RuleBasedMusicSource] → 注册进 [SourceManager]。
/// 这是 uiv2 订阅页 [SubscriptionHost] 的真实实现（此前宿主为空，页面只能显示占位说明）。
library;

import 'dart:convert';
// 用前缀：crawler 也导出了同名 HttpClient，不前缀会解析到对方的类型
import 'dart:io' as io;

import 'package:core/core.dart';
import 'package:crawler/crawler.dart';
import 'package:uiv2/uiv2.dart' show SubscriptionHost;

/// 一条订阅记录（持久化的最小字段）
class SubscriptionEntry {
  /// 远程地址
  final String url;

  /// 展开后得到的源 id（用于更新时先反注册）
  final String sourceId;

  /// 备注名（可空）
  final String? alias;

  /// 构造
  const SubscriptionEntry({
    required this.url,
    required this.sourceId,
    this.alias,
  });

  /// 序列化
  Map<String, dynamic> toJson() => {
        'url': url,
        'sourceId': sourceId,
        'alias': alias,
      };

  /// 反序列化（脏数据返回 null，不抛）
  static SubscriptionEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final url = raw['url'];
    final sourceId = raw['sourceId'];
    if (url is! String || sourceId is! String) return null;
    final alias = raw['alias'];
    return SubscriptionEntry(
      url: url,
      sourceId: sourceId,
      alias: alias is String ? alias : null,
    );
  }
}

/// 订阅库
class SubscriptionLibrary {
  /// settings 表里的键
  static const String settingsKey = 'subscriptions';

  /// 设置表（持久化订阅列表）
  final SettingsDao settingsDao;

  /// 源管理器（展开/更新时注册与反注册）
  final SourceManager sourceManager;

  final List<SubscriptionEntry> _entries = [];

  /// 构造
  SubscriptionLibrary({required this.settingsDao, required this.sourceManager});

  /// 首次加载：只读持久化列表，不自动联网刷新（避免启动阻塞）
  Future<void> load() async {
    _entries.clear();
    final raw = await settingsDao.get(settingsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          final entry = SubscriptionEntry.fromJson(item);
          if (entry != null) _entries.add(entry);
        }
      }
    } catch (_) {
      // 存储损坏时按"没有订阅"处理，不阻塞启动
    }
  }

  /// 当前订阅条数
  int get count => _entries.length;

  /// 已订阅的地址（供 UI 展示）
  List<String> get urls => [for (final e in _entries) e.url];

  Future<void> _save() async {
    await settingsDao.set(
      settingsKey,
      jsonEncode([for (final e in _entries) e.toJson()]),
    );
  }

  /// 拉取并解析一个规则 JSON；任何失败都返回 null（调用方据此报错）
  Future<RuleConfig?> _fetchRule(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    const timeout = Duration(seconds: 15);
    final client = io.HttpClient();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return null;
      final text =
          await response.transform(utf8.decoder).join().timeout(timeout);
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return null;
      return RuleConfig.fromJson(decoded);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  void _register(RuleConfig config) {
    sourceManager.registerSource(RuleBasedMusicSource(config));
    sourceManager.setSourceEnabled(config.source.id, true);
  }

  /// 添加订阅
  Future<bool> add(String url, String type, String? alias) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    if (_entries.any((e) => e.url == trimmed)) return false;
    final config = await _fetchRule(trimmed);
    if (config == null) return false;
    _register(config);
    _entries.add(SubscriptionEntry(
      url: trimmed,
      sourceId: config.source.id,
      alias: alias,
    ));
    await _save();
    return true;
  }

  /// 删除订阅
  Future<void> remove(String url) async {
    final index = _entries.indexWhere((e) => e.url == url);
    if (index < 0) return;
    final entry = _entries.removeAt(index);
    sourceManager.unregisterSource(entry.sourceId);
    await _save();
  }

  /// 检查全部更新：重新拉取并替换源，返回 (成功数, 失败数)
  Future<(int, int)> checkAll() async {
    var ok = 0;
    var fail = 0;
    for (final old in List<SubscriptionEntry>.of(_entries)) {
      final config = await _fetchRule(old.url);
      if (config == null) {
        fail++;
        continue;
      }
      sourceManager.unregisterSource(old.sourceId);
      _register(config);
      final index = _entries.indexOf(old);
      if (index >= 0) {
        _entries[index] = SubscriptionEntry(
          url: old.url,
          sourceId: config.source.id,
          alias: old.alias,
        );
      }
      ok++;
    }
    await _save();
    return (ok, fail);
  }

  /// 交给 uiv2 的注入点
  SubscriptionHost get host => SubscriptionHost(
        count: () => _entries.length,
        add: add,
        remove: remove,
        checkAll: checkAll,
      );
}
