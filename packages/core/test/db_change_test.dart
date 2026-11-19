// DbChangeBus 单测：验证同步层的「变更感知」信号可靠
//
// 覆盖：基本广播、多订阅者、dispose 后 emit 不抛。
// 不含 DB：本测试只验证纯 Dart 的总线行为。

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('emit 后订阅者收到对应实体事件', () async {
    final bus = DbChangeBus();
    final received = bus.changes.first;
    bus.emit(DbEntity.favorites);
    final change = await received;
    expect(change.entity, DbEntity.favorites);
    expect(change.at, isA<DateTime>());
    await bus.dispose();
  });

  test('广播：多个订阅者都能收到同一事件', () async {
    final bus = DbChangeBus();
    final first = bus.changes.first;
    final second = bus.changes.first;
    bus.emit(DbEntity.progress);
    expect((await first).entity, DbEntity.progress);
    expect((await second).entity, DbEntity.progress);
    await bus.dispose();
  });

  test('dispose 之后 emit 不抛异常（静默忽略）', () async {
    final bus = DbChangeBus();
    await bus.dispose();
    expect(() => bus.emit(DbEntity.songs), returnsNormally);
  });

  test('downloads 不在 DbEntity 里（下载属设备本地，不参与云同步）', () {
    expect(DbEntity.values.map((e) => e.name), isNot(contains('downloads')));
  });
}
