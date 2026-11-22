/// 订阅库：规则内容持久化 + 换机离线展开（真实本地 HTTP + 真实 DAO）
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:crawler/crawler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resonance_app/subscription_library.dart';

/// 最小可用规则：只有 source（其余流程缺省）
String ruleJson(String id, String name) =>
    jsonEncode(<String, dynamic>{
      'source': <String, dynamic>{'id': id, 'name': name},
    });

void main() {
  test('添加订阅落盘规则内容；断网后仍可在新设备展开', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final url = 'http://127.0.0.1:${server.port}/rule.json';
    server.listen((req) async {
      req.response.headers.contentType = ContentType.json;
      req.response.write(ruleJson('offline_src', '离线源'));
      await req.response.close();
    });

    final db = InMemoryDatabaseProvider();
    await db.initialize();
    final sm = SourceManager();
    final lib = SubscriptionLibrary(settingsDao: db.settingsDao, sourceManager: sm);

    expect(await lib.add(url, 'rule', '我的订阅'), isTrue);
    final raw = await db.settingsDao.get(SubscriptionLibrary.settingsKey);
    expect(raw, isNotNull);
    final list = jsonDecode(raw!) as List<dynamic>;
    expect((list.single as Map)['rule'], isA<String>());
    expect(sm.isSourceEnabled('offline_src'), isTrue);

    // 模拟换机：服务器关闭，从同一份 settings 恢复
    await server.close(force: true);
    final sm2 = SourceManager();
    final lib2 = SubscriptionLibrary(settingsDao: db.settingsDao, sourceManager: sm2);
    await lib2.load();
    expect(lib2.count, 1);
    expect(sm2.getAllSources(), isEmpty, reason: 'load 不自动联网展开');

    final (ok, fail) = await lib2.checkAll();
    expect(ok, 1);
    expect(fail, 0);
    expect(sm2.isSourceEnabled('offline_src'), isTrue, reason: '用落盘规则离线展开');
  });
}
