/// DirectoryAssetStore 测试
///
/// 覆盖：
///   1. 前缀白名单：只镜像指定目录，其它文件不参与同步；
///   2. 写入保留 mtime、删除按路径。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync/sync.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('asset_store_test');
    // 订阅目录（要同步）
    Directory('${tmp.path}/subscriptions').createSync(recursive: true);
    File('${tmp.path}/subscriptions/index.json').writeAsStringSync('[]');
    // 其它文件（不该同步）
    File('${tmp.path}/resonance.db').writeAsStringSync('db');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('前缀白名单：只镜像 subscriptions/', () async {
    const store = DirectoryAssetStore('', prefixes: <String>['subscriptions/']);
    final real = DirectoryAssetStore(tmp.path, prefixes: const <String>['subscriptions/']);
    // 上面用 real 实际读取（const 只用于验证构造签名）
    expect(store.prefixes, isNotEmpty);

    final files = await real.readAll();
    expect(files.map((f) => f.path), contains('subscriptions/index.json'));
    expect(files.map((f) => f.path), isNot(contains('resonance.db')));
  });

  test('写入保留 mtime，删除按路径', () async {
    final store = DirectoryAssetStore(tmp.path);
    await store.write(<AssetFile>[
      AssetFile(
        path: 'subscriptions/new.json',
        bytes: <int>[1, 2, 3],
        mtime: 1234000,
      ),
    ]);
    final read = await store.readAll();
    final added = read.firstWhere((f) => f.path == 'subscriptions/new.json');
    expect(added.bytes, <int>[1, 2, 3]);
    expect(added.mtime, 1234000);

    await store.delete(<String>['subscriptions/new.json']);
    expect(
      (await store.readAll()).map((f) => f.path),
      isNot(contains('subscriptions/new.json')),
    );
  });
}
